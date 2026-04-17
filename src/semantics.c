#include "semantics.h"

#include <errno.h>
#include <limits.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum semantic_type {
    TYPE_INT,
    TYPE_DOUBLE,
    TYPE_BOOLEAN,
    TYPE_STRING_ARRAY,
    TYPE_VOID,
    TYPE_UNDEF
};

enum symbol_kind {
    SYMBOL_FIELD,
    SYMBOL_METHOD,
    SYMBOL_PARAM,
    SYMBOL_LOCAL,
    SYMBOL_RETURN
};

struct table_entry {
    char *name;
    enum semantic_type type;
    enum symbol_kind kind;
    int in_scope;
    struct table_entry *next;
};

struct method_info {
    struct node *body_node;
    char *name;
    enum semantic_type return_type;
    int param_count;
    enum semantic_type *param_types;
    char *signature;
    int show_table;
    int can_resolve_calls;
    struct table_entry *entries;
    struct table_entry *entries_tail;
    struct method_info *next;
};

struct class_symbol {
    char *name;
    enum symbol_kind kind;
    enum semantic_type type;
    int param_count;
    enum semantic_type *param_types;
    char *signature;
    struct class_symbol *next;
};

struct semantic_error {
    int line;
    int column;
    char *message;
};

static char *class_name;
static struct class_symbol *class_symbols;
static struct class_symbol *class_symbols_tail;
static struct method_info *methods;
static struct method_info *methods_tail;
static struct method_info *current_method;

static struct semantic_error *semantic_errors;
static int semantic_error_count;
static int semantic_error_capacity;

/* Private semantic pass helpers. */
static enum semantic_type check_expression(struct node *node);
static enum semantic_type check_call(struct node *node);
static enum semantic_type check_assignment(struct node *node);
static enum semantic_type check_parse_args(struct node *node);
static enum semantic_type check_length(struct node *node);
static enum semantic_type check_boolean_binary(struct node *node);
static enum semantic_type check_equality(struct node *node);
static enum semantic_type check_relational(struct node *node);
static enum semantic_type check_arithmetic(struct node *node);
static enum semantic_type check_shift(struct node *node);
static enum semantic_type check_xor(struct node *node);
static enum semantic_type check_unary_numeric(struct node *node);
static enum semantic_type check_not(struct node *node);

static char *dup_string(const char *text) {
    if (text == NULL) return NULL;

    char *copy = malloc(strlen(text) + 1);
    strcpy(copy, text);
    return copy;
}

static const char *type_name(enum semantic_type type) {
    switch (type) {
        case TYPE_INT:
            return "int";
        case TYPE_DOUBLE:
            return "double";
        case TYPE_BOOLEAN:
            return "boolean";
        case TYPE_STRING_ARRAY:
            return "String[]";
        case TYPE_VOID:
            return "void";
        case TYPE_UNDEF:
            return "undef";
    }

    return "undef";
}

static enum semantic_type node_type(struct node *node) {
    if (node == NULL) return TYPE_UNDEF;

    switch (node->category) {
        case Int:
            return TYPE_INT;
        case Double:
            return TYPE_DOUBLE;
        case Bool:
            return TYPE_BOOLEAN;
        case StringArray:
            return TYPE_STRING_ARRAY;
        case Void:
            return TYPE_VOID;
        default:
            return TYPE_UNDEF;
    }
}

static int is_numeric(enum semantic_type type) {
    return type == TYPE_INT || type == TYPE_DOUBLE;
}

static int is_printable_scalar(enum semantic_type type) {
    return type == TYPE_INT || type == TYPE_DOUBLE || type == TYPE_BOOLEAN;
}

static int is_compatible(enum semantic_type expected,
                         enum semantic_type actual) {
    if (expected == TYPE_UNDEF || actual == TYPE_UNDEF) return 0;
    if (expected == actual) return 1;
    if (expected == TYPE_DOUBLE && actual == TYPE_INT) return 1;

    return 0;
}

static int same_signature(int count_a, enum semantic_type *types_a, int count_b,
                          enum semantic_type *types_b) {
    int i;

    if (count_a != count_b) return 0;

    for (i = 0; i < count_a; i++) {
        if (types_a[i] != types_b[i]) return 0;
    }

    return 1;
}

static char *build_signature(int count, enum semantic_type *types) {
    size_t size = 3;
    int i;
    char *signature;

    for (i = 0; i < count; i++) {
        size += strlen(type_name(types[i])) + 1;
    }

    signature = malloc(size);
    signature[0] = '(';
    signature[1] = '\0';

    for (i = 0; i < count; i++) {
        strcat(signature, type_name(types[i]));
        if (i + 1 < count) strcat(signature, ",");
    }

    strcat(signature, ")");
    return signature;
}

static void ensure_error_capacity(void) {
    if (semantic_error_count < semantic_error_capacity) return;

    semantic_error_capacity =
        semantic_error_capacity == 0 ? 8 : semantic_error_capacity * 2;
    semantic_errors =
        realloc(semantic_errors,
                semantic_error_capacity * sizeof(struct semantic_error));
}

static void add_error(int line, int column, const char *format, ...) {
    va_list args;
    char buffer[512];

    ensure_error_capacity();

    va_start(args, format);
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);

    semantic_errors[semantic_error_count].line = line;
    semantic_errors[semantic_error_count].column = column;
    semantic_errors[semantic_error_count].message = dup_string(buffer);
    semantic_error_count++;
}

static const char *binary_operator_name(enum category category) {
    switch (category) {
        case Or:
            return "||";
        case And:
            return "&&";
        case Eq:
            return "==";
        case Ne:
            return "!=";
        case Lt:
            return "<";
        case Gt:
            return ">";
        case Le:
            return "<=";
        case Ge:
            return ">=";
        case Add:
            return "+";
        case Sub:
            return "-";
        case Mul:
            return "*";
        case Div:
            return "/";
        case Mod:
            return "%";
        case Lshift:
            return "<<";
        case Rshift:
            return ">>";
        case Xor:
            return "^";
        case Assign:
            return "=";
        default:
            return "";
    }
}

static const char *unary_operator_name(enum category category) {
    switch (category) {
        case Not:
            return "!";
        case Minus:
            return "-";
        case Plus:
            return "+";
        case Length:
            return ".length";
        default:
            return "";
    }
}

static const char *statement_name(enum category category) {
    switch (category) {
        case If:
            return "if";
        case While:
            return "while";
        case Return:
            return "return";
        case Print:
            return "System.out.print";
        default:
            return "";
    }
}

static void annotate_type(struct node *node, enum semantic_type type) {
    set_annotation(node, type_name(type));
}

static struct table_entry *new_table_entry(const char *name,
                                           enum semantic_type type,
                                           enum symbol_kind kind) {
    struct table_entry *entry = malloc(sizeof(struct table_entry));

    entry->name = dup_string(name);
    entry->type = type;
    entry->kind = kind;
    entry->in_scope = kind != SYMBOL_LOCAL;
    entry->next = NULL;
    return entry;
}

static void append_method_entry(struct method_info *method, const char *name,
                                enum semantic_type type,
                                enum symbol_kind kind) {
    struct table_entry *entry = new_table_entry(name, type, kind);

    if (method->entries == NULL) {
        method->entries = entry;
        method->entries_tail = entry;
    } else {
        method->entries_tail->next = entry;
        method->entries_tail = entry;
    }
}

static struct class_symbol *new_class_symbol(
    const char *name, enum symbol_kind kind, enum semantic_type type,
    int param_count, enum semantic_type *param_types, const char *signature) {
    struct class_symbol *symbol = malloc(sizeof(struct class_symbol));

    symbol->name = dup_string(name);
    symbol->kind = kind;
    symbol->type = type;
    symbol->param_count = param_count;
    symbol->param_types = param_types;
    symbol->signature = dup_string(signature);
    symbol->next = NULL;

    return symbol;
}

static void append_class_symbol(struct class_symbol *symbol) {
    if (class_symbols == NULL) {
        class_symbols = symbol;
        class_symbols_tail = symbol;
    } else {
        class_symbols_tail->next = symbol;
        class_symbols_tail = symbol;
    }
}

static void append_method(struct method_info *method) {
    if (methods == NULL) {
        methods = method;
        methods_tail = method;
    } else {
        methods_tail->next = method;
        methods_tail = method;
    }
}

static struct class_symbol *find_field(const char *name) {
    struct class_symbol *symbol;

    for (symbol = class_symbols; symbol != NULL; symbol = symbol->next) {
        if (symbol->kind == SYMBOL_FIELD && strcmp(symbol->name, name) == 0)
            return symbol;
    }

    return NULL;
}

static struct class_symbol *find_method_symbol(
    const char *name, int param_count, enum semantic_type *param_types) {
    struct class_symbol *symbol;

    for (symbol = class_symbols; symbol != NULL; symbol = symbol->next) {
        if (symbol->kind != SYMBOL_METHOD) continue;
        if (strcmp(symbol->name, name) != 0) continue;
        if (same_signature(symbol->param_count, symbol->param_types,
                           param_count, param_types))
            return symbol;
    }

    return NULL;
}

static struct table_entry *find_method_entry(struct method_info *method,
                                             const char *name,
                                             int in_scope_only) {
    struct table_entry *entry;

    for (entry = method->entries; entry != NULL; entry = entry->next) {
        if (entry->kind == SYMBOL_RETURN) continue;
        if (in_scope_only && !entry->in_scope) continue;
        if (strcmp(entry->name, name) == 0) return entry;
    }

    return NULL;
}

static struct table_entry *find_method_variable(struct method_info *method,
                                                const char *name) {
    return find_method_entry(method, name, 1);
}

static void clear_annotations(struct node *node) {
    struct node_list *child;

    if (node == NULL) return;

    set_annotation(node, NULL);

    for (child = node->children; child != NULL; child = child->next) {
        clear_annotations(child->node);
    }
}

static int is_reserved_symbol(const char *name) {
    return strcmp(name, "_") == 0;
}

static int natural_out_of_bounds(const char *token) {
    char digits[64];
    int i;
    int j = 0;

    for (i = 0; token[i] != '\0' && j < (int)(sizeof(digits) - 1); i++) {
        if (token[i] != '_') digits[j++] = token[i];
    }
    digits[j] = '\0';

    if (j > 10) return 1;
    if (j < 10) return 0;

    return strcmp(digits, "2147483647") > 0;
}

static int decimal_out_of_bounds(const char *token) {
    char clean[256];
    int i;
    int j = 0;
    int has_non_zero_digit = 0;
    char *end = NULL;
    double value;

    for (i = 0; token[i] != '\0' && j < (int)(sizeof(clean) - 1); i++) {
        if (token[i] == '_') continue;
        if (token[i] >= '1' && token[i] <= '9') has_non_zero_digit = 1;
        clean[j++] = token[i];
    }
    clean[j] = '\0';

    errno = 0;
    value = strtod(clean, &end);

    if (end == clean) return 0;
    if (errno != ERANGE) return 0;
    if (value == HUGE_VAL || value == -HUGE_VAL) return 1;
    if (value == 0.0 && has_non_zero_digit) return 1;

    return 0;
}

static void add_duplicate_symbol_error(struct node *id) {
    add_error(id->line, id->column, "Symbol %s already defined", id->token);
}

static void add_duplicate_method_error(struct node *id, const char *signature) {
    add_error(id->line, id->column, "Symbol %s%s already defined", id->token,
              signature);
}

static void collect_field(struct node *field_decl) {
    struct node *id = get_child(field_decl, 1);
    enum semantic_type type = node_type(get_child(field_decl, 0));

    if (is_reserved_symbol(id->token)) {
        add_error(id->line, id->column, "Symbol _ is reserved");
        return;
    }

    if (find_field(id->token) != NULL) {
        add_duplicate_symbol_error(id);
        return;
    }

    append_class_symbol(
        new_class_symbol(id->token, SYMBOL_FIELD, type, 0, NULL, NULL));
}

static void collect_method_symbol(struct method_info *method, struct node *id) {
    if (is_reserved_symbol(method->name)) {
        add_error(id->line, id->column, "Symbol _ is reserved");
        method->can_resolve_calls = 0;
        method->show_table = 0;
        return;
    }

    if (find_method_symbol(method->name, method->param_count,
                           method->param_types) != NULL) {
        add_duplicate_method_error(id, method->signature);
        method->can_resolve_calls = 0;
        method->show_table = 0;
        return;
    }

    append_class_symbol(new_class_symbol(
        method->name, SYMBOL_METHOD, method->return_type, method->param_count,
        method->param_types, method->signature));
}

static void collect_method_entry(struct method_info *method, struct node *id,
                                 enum semantic_type type,
                                 enum symbol_kind kind) {
    if (is_reserved_symbol(id->token)) {
        add_error(id->line, id->column, "Symbol _ is reserved");
        return;
    }

    if (find_method_entry(method, id->token, 0) != NULL) {
        add_duplicate_symbol_error(id);
        return;
    }

    append_method_entry(method, id->token, type, kind);
}

static void collect_method(struct node *method_decl) {
    struct node *header = get_child(method_decl, 0);
    struct node *body = get_child(method_decl, 1);
    struct node *return_node = get_child(header, 0);
    struct node *id = get_child(header, 1);
    struct node *params = get_child(header, 2);
    struct method_info *method = calloc(1, sizeof(struct method_info));
    struct node_list *param_child;
    int index = 0;

    method->body_node = body;
    method->name = id->token;
    method->return_type = node_type(return_node);
    method->param_count = child_count(params);
    method->can_resolve_calls = 1;
    method->show_table = 1;

    if (method->param_count > 0) {
        method->param_types =
            malloc(method->param_count * sizeof(enum semantic_type));
    }

    append_method_entry(method, "return", method->return_type, SYMBOL_RETURN);

    for (param_child = params->children; param_child != NULL;
         param_child = param_child->next) {
        struct node *param = param_child->node;
        enum semantic_type type = node_type(get_child(param, 0));
        struct node *param_id = get_child(param, 1);

        method->param_types[index++] = type;
        collect_method_entry(method, param_id, type, SYMBOL_PARAM);
    }

    method->signature =
        build_signature(method->param_count, method->param_types);
    collect_method_symbol(method, id);

    append_method(method);
}

static void build_symbol_tables(struct node *program) {
    struct node_list *child;
    struct node *class_id = get_child(program, 0);

    class_name = class_id == NULL ? NULL : class_id->token;

    child = program->children;
    if (child != NULL) child = child->next;

    while (child != NULL) {
        if (child->node->category == FieldDecl) collect_field(child->node);
        if (child->node->category == MethodDecl) collect_method(child->node);
        child = child->next;
    }
}

static enum semantic_type resolve_identifier(struct node *id) {
    struct table_entry *entry;
    struct class_symbol *field;

    if (id == NULL) return TYPE_UNDEF;

    if (is_reserved_symbol(id->token)) {
        add_error(id->line, id->column, "Symbol _ is reserved");
        annotate_type(id, TYPE_UNDEF);
        return TYPE_UNDEF;
    }

    if (current_method != NULL) {
        entry = find_method_variable(current_method, id->token);
        if (entry != NULL) {
            annotate_type(id, entry->type);
            return entry->type;
        }
    }

    field = find_field(id->token);
    if (field != NULL) {
        annotate_type(id, field->type);
        return field->type;
    }

    add_error(id->line, id->column, "Cannot find symbol %s", id->token);
    annotate_type(id, TYPE_UNDEF);
    return TYPE_UNDEF;
}

static void add_binary_operator_error(struct node *node,
                                      enum semantic_type left,
                                      enum semantic_type right) {
    add_error(node->line, node->column,
              "Operator %s cannot be applied to types %s, %s",
              binary_operator_name(node->category), type_name(left),
              type_name(right));
}

static void add_unary_operator_error(struct node *node,
                                     enum semantic_type type) {
    add_error(node->line, node->column,
              "Operator %s cannot be applied to type %s",
              unary_operator_name(node->category), type_name(type));
}

static struct method_info *resolve_method_call(const char *name, int argc,
                                               enum semantic_type *arg_types,
                                               int *compatible_count) {
    struct method_info *exact_match = NULL;
    struct method_info *compatible_match = NULL;
    struct method_info *method;

    *compatible_count = 0;

    for (method = methods; method != NULL; method = method->next) {
        int i;
        int exact = 1;
        int compatible = 1;

        if (!method->can_resolve_calls) continue;
        if (strcmp(method->name, name) != 0) continue;
        if (method->param_count != argc) continue;

        for (i = 0; i < argc; i++) {
            if (method->param_types[i] != arg_types[i]) exact = 0;
            if (!is_compatible(method->param_types[i], arg_types[i]))
                compatible = 0;
        }

        if (exact) return method;
        if (compatible) {
            compatible_match = method;
            (*compatible_count)++;
        }
    }

    if (*compatible_count == 1) exact_match = compatible_match;
    return exact_match;
}

static enum semantic_type check_call(struct node *node) {
    struct node *id = get_child(node, 0);
    enum semantic_type *arg_types;
    int arg_count = child_count(node) - 1;
    int i = 0;
    int compatible_count = 0;
    struct node_list *child;
    struct method_info *method;
    char *signature;
    char *attempted_signature;

    arg_types =
        arg_count > 0 ? malloc(arg_count * sizeof(enum semantic_type)) : NULL;

    child = node->children;
    if (child != NULL) child = child->next;

    while (child != NULL) {
        arg_types[i] = check_expression(child->node);
        child = child->next;
        i++;
    }

    if (is_reserved_symbol(id->token)) {
        add_error(id->line, id->column, "Symbol _ is reserved");
        annotate_type(id, TYPE_UNDEF);
        annotate_type(node, TYPE_UNDEF);
        free(arg_types);
        return TYPE_UNDEF;
    }

    attempted_signature = build_signature(arg_count, arg_types);
    method =
        resolve_method_call(id->token, arg_count, arg_types, &compatible_count);
    if (method == NULL) {
        if (compatible_count > 1) {
            add_error(id->line, id->column,
                      "Reference to method %s%s is ambiguous", id->token,
                      attempted_signature);
        } else {
            add_error(id->line, id->column, "Cannot find symbol %s%s",
                      id->token, attempted_signature);
        }

        annotate_type(id, TYPE_UNDEF);
        annotate_type(node, TYPE_UNDEF);
        free(attempted_signature);
        free(arg_types);
        return TYPE_UNDEF;
    }

    signature = build_signature(method->param_count, method->param_types);
    set_annotation(id, signature);
    free(signature);
    annotate_type(node, method->return_type);
    free(attempted_signature);
    free(arg_types);
    return method->return_type;
}

static enum semantic_type arithmetic_result(enum semantic_type left,
                                            enum semantic_type right) {
    if (left == TYPE_DOUBLE || right == TYPE_DOUBLE) return TYPE_DOUBLE;
    return TYPE_INT;
}

static enum semantic_type check_assignment(struct node *node) {
    struct node *left = get_child(node, 0);
    struct node *right = get_child(node, 1);
    enum semantic_type left_type = resolve_identifier(left);
    enum semantic_type right_type = check_expression(right);

    if (left_type != TYPE_STRING_ARRAY && right_type != TYPE_STRING_ARRAY &&
        is_compatible(left_type, right_type)) {
        annotate_type(node, left_type);
        return left_type;
    }

    add_binary_operator_error(node, left_type, right_type);
    annotate_type(node, left_type);
    return left_type;
}

static enum semantic_type check_parse_args(struct node *node) {
    struct node *left = get_child(node, 0);
    struct node *right = get_child(node, 1);
    enum semantic_type left_type = resolve_identifier(left);
    enum semantic_type right_type = check_expression(right);

    if (!(left_type == TYPE_STRING_ARRAY && right_type == TYPE_INT)) {
        add_error(node->line, node->column,
                  "Operator Integer.parseInt cannot be applied to types %s, %s",
                  type_name(left_type), type_name(right_type));
    }

    /* Recovery rule required by meta3 output: parseInt keeps its int type. */
    annotate_type(node, TYPE_INT);
    return TYPE_INT;
}

static enum semantic_type check_length(struct node *node) {
    struct node *left = get_child(node, 0);
    enum semantic_type left_type = resolve_identifier(left);

    if (left_type != TYPE_STRING_ARRAY) add_unary_operator_error(node, left_type);

    /* Recovery rule required by meta3 output: .length keeps its int type. */
    annotate_type(node, TYPE_INT);
    return TYPE_INT;
}

static enum semantic_type check_boolean_binary(struct node *node) {
    enum semantic_type left_type = check_expression(get_child(node, 0));
    enum semantic_type right_type = check_expression(get_child(node, 1));

    if (!(left_type == TYPE_BOOLEAN && right_type == TYPE_BOOLEAN))
        add_binary_operator_error(node, left_type, right_type);

    /* Recovery rule required by meta3 output: boolean ops stay boolean. */
    annotate_type(node, TYPE_BOOLEAN);
    return TYPE_BOOLEAN;
}

static enum semantic_type check_equality(struct node *node) {
    enum semantic_type left_type = check_expression(get_child(node, 0));
    enum semantic_type right_type = check_expression(get_child(node, 1));

    if (!((is_numeric(left_type) && is_numeric(right_type)) ||
          (left_type == TYPE_BOOLEAN && right_type == TYPE_BOOLEAN)))
        add_binary_operator_error(node, left_type, right_type);

    /* Recovery rule required by meta3 output: equality keeps boolean type. */
    annotate_type(node, TYPE_BOOLEAN);
    return TYPE_BOOLEAN;
}

static enum semantic_type check_relational(struct node *node) {
    enum semantic_type left_type = check_expression(get_child(node, 0));
    enum semantic_type right_type = check_expression(get_child(node, 1));

    if (!(is_numeric(left_type) && is_numeric(right_type)))
        add_binary_operator_error(node, left_type, right_type);

    /* Recovery rule required by meta3 output: comparisons keep boolean type. */
    annotate_type(node, TYPE_BOOLEAN);
    return TYPE_BOOLEAN;
}

static enum semantic_type check_arithmetic(struct node *node) {
    enum semantic_type left_type = check_expression(get_child(node, 0));
    enum semantic_type right_type = check_expression(get_child(node, 1));

    if (is_numeric(left_type) && is_numeric(right_type)) {
        annotate_type(node, arithmetic_result(left_type, right_type));
        return arithmetic_result(left_type, right_type);
    }

    add_binary_operator_error(node, left_type, right_type);
    annotate_type(node, TYPE_UNDEF);
    return TYPE_UNDEF;
}

static enum semantic_type check_shift(struct node *node) {
    enum semantic_type left_type = check_expression(get_child(node, 0));
    enum semantic_type right_type = check_expression(get_child(node, 1));

    if (left_type == TYPE_INT && right_type == TYPE_INT) {
        annotate_type(node, TYPE_INT);
        return TYPE_INT;
    }

    add_binary_operator_error(node, left_type, right_type);
    annotate_type(node, TYPE_UNDEF);
    return TYPE_UNDEF;
}

static enum semantic_type check_xor(struct node *node) {
    enum semantic_type left_type = check_expression(get_child(node, 0));
    enum semantic_type right_type = check_expression(get_child(node, 1));

    if (left_type == TYPE_INT && right_type == TYPE_INT) {
        annotate_type(node, TYPE_INT);
        return TYPE_INT;
    }

    if (left_type == TYPE_BOOLEAN && right_type == TYPE_BOOLEAN) {
        annotate_type(node, TYPE_BOOLEAN);
        return TYPE_BOOLEAN;
    }

    add_binary_operator_error(node, left_type, right_type);
    annotate_type(node, TYPE_UNDEF);
    return TYPE_UNDEF;
}

static enum semantic_type check_unary_numeric(struct node *node) {
    enum semantic_type type = check_expression(get_child(node, 0));

    if (is_numeric(type)) {
        annotate_type(node, type);
        return type;
    }

    add_unary_operator_error(node, type);
    annotate_type(node, TYPE_UNDEF);
    return TYPE_UNDEF;
}

static enum semantic_type check_not(struct node *node) {
    enum semantic_type type = check_expression(get_child(node, 0));

    if (type == TYPE_BOOLEAN) {
        annotate_type(node, TYPE_BOOLEAN);
        return TYPE_BOOLEAN;
    }

    add_unary_operator_error(node, type);
    annotate_type(node, TYPE_UNDEF);
    return TYPE_UNDEF;
}

static enum semantic_type check_expression(struct node *node) {
    if (node == NULL) return TYPE_UNDEF;

    switch (node->category) {
        case Identifier:
            return resolve_identifier(node);

        case Natural:
            if (natural_out_of_bounds(node->token)) {
                add_error(node->line, node->column, "Number %s out of bounds",
                          node->token);
            }
            annotate_type(node, TYPE_INT);
            return TYPE_INT;

        case Decimal:
            if (decimal_out_of_bounds(node->token)) {
                add_error(node->line, node->column, "Number %s out of bounds",
                          node->token);
            }
            annotate_type(node, TYPE_DOUBLE);
            return TYPE_DOUBLE;

        case BoolLit:
            annotate_type(node, TYPE_BOOLEAN);
            return TYPE_BOOLEAN;

        case Call:
            return check_call(node);

        case ParseArgs:
            return check_parse_args(node);

        case Length:
            return check_length(node);

        case Assign:
            return check_assignment(node);

        case Or:
        case And:
            return check_boolean_binary(node);

        case Eq:
        case Ne:
            return check_equality(node);

        case Lt:
        case Gt:
        case Le:
        case Ge:
            return check_relational(node);

        case Add:
        case Sub:
        case Mul:
        case Div:
        case Mod:
            return check_arithmetic(node);

        case Lshift:
        case Rshift:
            return check_shift(node);

        case Xor:
            return check_xor(node);

        case Minus:
        case Plus:
            return check_unary_numeric(node);

        case Not:
            return check_not(node);

        default:
            return TYPE_UNDEF;
    }
}

static void add_statement_type_error(struct node *location,
                                     enum category statement_category,
                                     enum semantic_type type) {
    add_error(location->line, location->column,
              "Incompatible type %s in %s statement", type_name(type),
              statement_name(statement_category));
}

static void check_statement(struct node *node) {
    struct node_list *child;
    enum semantic_type type;

    if (node == NULL) return;

    switch (node->category) {
        case Block:
            for (child = node->children; child != NULL; child = child->next) {
                check_statement(child->node);
            }
            break;

        case If:
            type = check_expression(get_child(node, 0));
            if (type != TYPE_BOOLEAN)
                add_statement_type_error(get_child(node, 0), node->category,
                                         type);
            check_statement(get_child(node, 1));
            check_statement(get_child(node, 2));
            break;

        case While:
            type = check_expression(get_child(node, 0));
            if (type != TYPE_BOOLEAN)
                add_statement_type_error(get_child(node, 0), node->category,
                                         type);
            check_statement(get_child(node, 1));
            break;

        case Return:
            if (get_child(node, 0) == NULL) {
                if (current_method->return_type != TYPE_VOID)
                    add_statement_type_error(node, node->category, TYPE_VOID);
                break;
            }

            type = check_expression(get_child(node, 0));
            if (current_method->return_type == TYPE_VOID ||
                !is_compatible(current_method->return_type, type))
                add_statement_type_error(get_child(node, 0), node->category,
                                         type);
            break;

        case Print:
            if (get_child(node, 0) != NULL &&
                get_child(node, 0)->category == StrLit)
                break;

            type = check_expression(get_child(node, 0));
            if (!is_printable_scalar(type))
                add_statement_type_error(get_child(node, 0), node->category,
                                         type);
            break;

        case Assign:
        case Call:
        case ParseArgs:
            (void)check_expression(node);
            break;

        default:
            break;
    }
}

static void collect_local_declaration(struct method_info *method,
                                      struct node *var_decl) {
    struct node *id = get_child(var_decl, 1);
    enum semantic_type type = node_type(get_child(var_decl, 0));

    if (is_reserved_symbol(id->token)) {
        add_error(id->line, id->column, "Symbol _ is reserved");
        return;
    }

    if (find_method_entry(method, id->token, 0) != NULL) {
        add_duplicate_symbol_error(id);
        return;
    }

    append_method_entry(method, id->token, type, SYMBOL_LOCAL);
    method->entries_tail->in_scope = 1;
}

static void check_method(struct method_info *method) {
    struct node_list *child;

    if (!method->can_resolve_calls) return;

    current_method = method;

    for (child = method->body_node->children; child != NULL;
         child = child->next) {
        if (child->node == NULL) continue;
        if (child->node->category == VarDecl) {
            collect_local_declaration(method, child->node);
            continue;
        }
        check_statement(child->node);
    }
}

int check_program(struct node *program) {
    struct method_info *method;
    int i;

    class_name = NULL;
    class_symbols = NULL;
    class_symbols_tail = NULL;
    methods = NULL;
    methods_tail = NULL;
    current_method = NULL;
    semantic_error_count = 0;
    semantic_error_capacity = 0;
    semantic_errors = NULL;

    if (program == NULL) return 0;

    clear_annotations(program);
    build_symbol_tables(program);

    for (method = methods; method != NULL; method = method->next) {
        check_method(method);
    }

    for (i = 0; i < semantic_error_count; i++) {
        printf("Line %d, col %d: %s\n", semantic_errors[i].line,
               semantic_errors[i].column, semantic_errors[i].message);
    }

    return semantic_error_count;
}

void show_symbol_table(void) {
    struct class_symbol *symbol;
    struct method_info *method;
    printf("===== Class %s Symbol Table =====\n", class_name);
    for (symbol = class_symbols; symbol != NULL; symbol = symbol->next) {
        if (symbol->kind == SYMBOL_FIELD) {
            printf("%s\t\t%s\n", symbol->name, type_name(symbol->type));
        } else if (symbol->kind == SYMBOL_METHOD) {
            printf("%s\t%s\t%s\n", symbol->name, symbol->signature,
                   type_name(symbol->type));
        }
    }

    for (method = methods; method != NULL; method = method->next) {
        struct table_entry *entry;

        if (!method->show_table) continue;

        printf("\n");
        printf("===== Method %s%s Symbol Table =====\n", method->name,
               method->signature);

        for (entry = method->entries; entry != NULL; entry = entry->next) {
            printf("%s\t\t%s", entry->name, type_name(entry->type));
            if (entry->kind == SYMBOL_PARAM) printf("\tparam");
            printf("\n");
        }
    }
}

void print_annotated_tree(struct node *node, int depth) {
    struct node_list *child;
    int i;

    if (node == NULL) return;

    for (i = 0; i < depth; i++) {
        printf("..");
    }

    if (node->category == StrLit && node->token != NULL) {
        printf("%s(\"%s\")", category_name(node->category), node->token);
    } else if (node->token != NULL) {
        printf("%s(%s)", category_name(node->category), node->token);
    } else {
        printf("%s", category_name(node->category));
    }

    if (node->annotation != NULL) printf(" - %s", node->annotation);
    printf("\n");

    for (child = node->children; child != NULL; child = child->next) {
        print_annotated_tree(child->node, depth + 1);
    }
}
