#include "ast.h"

#include <stdio.h>
#include <stdlib.h>

// create a node of a given category with a given lexical symbol
struct node *new_node(enum category category, char *token) {
    struct node *new = malloc(sizeof(struct node));
    new->category = category;
    new->token = token;
    new->children = NULL;

    return new;
}

// append a node to the list of children of the parent node
void add_child(struct node *parent, struct node *child) {
    if (parent == NULL || child == NULL) return;

    struct node_list *new = malloc(sizeof(struct node_list));
    new->node = child;
    new->next = NULL;

    if (parent->children == NULL) {
        parent->children = new;
        return;
    }

    struct node_list *current = parent->children;
    while (current->next != NULL) current = current->next;
    current->next = new;
}

struct node *adopt1(enum category category, struct node *a) {
    struct node *parent = new_node(category, NULL);
    add_child(parent, a);

    return parent;
}

struct node *adopt2(enum category category, struct node *a, struct node *b) {
    struct node *parent = new_node(category, NULL);
    add_child(parent, a);
    add_child(parent, b);

    return parent;
}

struct node_list *new_list(struct node *node) {
    if (node == NULL) return NULL;

    struct node_list *list = malloc(sizeof(struct node_list));
    list->node = node;
    list->next = NULL;

    return list;
}

struct node_list *append_list(struct node_list *list, struct node *node) {
    if (node == NULL) return list;
    if (list == NULL) return new_list(node);

    struct node_list *current = list;
    while (current->next != NULL) current = current->next;
    current->next = new_list(node);

    return list;
}

struct node_list *join_lists(struct node_list *a, struct node_list *b) {
    if (a == NULL) return b;
    if (b == NULL) return a;

    struct node_list *current = a;
    while (current->next != NULL) current = current->next;
    current->next = b;
    return a;
}

// shallow copy for leaf nodes only
struct node *copy_leaf_node(struct node *node) {
    if (node == NULL) return NULL;

    struct node *copy = new_node(node->category, node->token);
    return copy;
}

void add_children(struct node *parent, struct node_list *list) {
    while (list != NULL) {
        add_child(parent, list->node);
        list = list->next;
    }
}

void print_tree(struct node *node, int depth) {
    if (node == NULL) return;

    for (int i = 0; i < depth; i++) {
        printf("..");
    }

    if (node->category == StrLit && node->token != NULL) {
        printf("%s(\"%s\")\n", category_name(node->category), node->token);
    } else if (node->token != NULL) {
        printf("%s(%s)\n", category_name(node->category), node->token);
    } else {
        printf("%s\n", category_name(node->category));
    }

    struct node_list *child = node->children;
    while (child != NULL) {
        print_tree(child->node, depth + 1);
        child = child->next;
    }
}

int child_count(struct node *node) {
    int count = 0;
    struct node_list *current = node->children;
    while (current != NULL) {
        count++;
        current = current->next;
    }
    return count;
}

char *category_name(enum category category) {
    switch (category) {
        case Program:
            return "Program";
        case FieldDecl:
            return "FieldDecl";
        case VarDecl:
            return "VarDecl";
        case MethodDecl:
            return "MethodDecl";
        case MethodHeader:
            return "MethodHeader";
        case MethodParams:
            return "MethodParams";
        case ParamDecl:
            return "ParamDecl";
        case MethodBody:
            return "MethodBody";
        case Block:
            return "Block";
        case If:
            return "If";
        case While:
            return "While";
        case Return:
            return "Return";
        case Print:
            return "Print";
        case ParseArgs:
            return "ParseArgs";
        case Assign:
            return "Assign";
        case Call:
            return "Call";
        case Or:
            return "Or";
        case And:
            return "And";
        case Eq:
            return "Eq";
        case Ne:
            return "Ne";
        case Lt:
            return "Lt";
        case Gt:
            return "Gt";
        case Le:
            return "Le";
        case Ge:
            return "Ge";
        case Add:
            return "Add";
        case Sub:
            return "Sub";
        case Mul:
            return "Mul";
        case Div:
            return "Div";
        case Mod:
            return "Mod";
        case Lshift:
            return "Lshift";
        case Rshift:
            return "Rshift";
        case Xor:
            return "Xor";
        case Not:
            return "Not";
        case Minus:
            return "Minus";
        case Plus:
            return "Plus";
        case Length:
            return "Length";
        case Bool:
            return "Bool";
        case BoolLit:
            return "BoolLit";
        case Double:
            return "Double";
        case Decimal:
            return "Decimal";
        case Identifier:
            return "Identifier";
        case Int:
            return "Int";
        case Natural:
            return "Natural";
        case StrLit:
            return "StrLit";
        case StringArray:
            return "StringArray";
        case Void:
            return "Void";
    }

    return "Unknown";
}
