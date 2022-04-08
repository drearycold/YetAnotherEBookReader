carthage update --no-build --verbose
for DEP in `cat Cartfile ./Carthage/Checkouts/*/Cartfile | fgrep github | awk '{print $2}' | sed -e 's/"//g' | awk -F'/' '{print $2}'`
do
	carthage build --platform ios --use-xcframeworks --cache-builds --no-use-binaries --verbose $DEP
done
