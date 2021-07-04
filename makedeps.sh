carthage update --no-build --use-submodules
for DEP in `cat Cartfile ./Carthage/Checkouts/*/Cartfile | fgrep github | fgrep -v readium | fgrep -v FolioReaderKit| awk '{print $2}' | sed -e 's/"//g' | awk -F'/' '{print $2}'`
do
	carthage build --platform ios --use-xcframeworks --cache-builds $DEP
done
