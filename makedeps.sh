carthage update --no-build --use-submodules
for DEP in `cat Cartfile ./Carthage/Checkouts/*/Cartfile | fgrep github | fgrep -v FolioReaderKit| awk '{print $2}' | sed -e 's/"//g' | awk -F'/' '{print $2}'`
do
	carthage build --platform ios,macos --use-xcframeworks --cache-builds --no-use-binaries $DEP
	#carthage build --platform ios --use-xcframeworks $DEP
done
