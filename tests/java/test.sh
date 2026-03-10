# examples:
# ./test.sh -l meta1
# ./test.sh -t meta2
for i in $2/*.java; do
    ../jucompiler $1 < "$i" | diff "${i/%.java}.out" -;
done
