#!/bin/sh

cd French.lproj
rm -rf Preferences*.nib
cvs update -d Preferences.nib
nibtool --use-oids --localizable-strings Preferences.nib > previous.strings
nibtool --use-oids --dictionary previous.strings -W Preferences_new.nib ../English.lproj/Preferences.nib
mv Preferences.nib Preferences_old.nib
mv Preferences_new.nib Preferences.nib
mv Preferences_old.nib/CVS Preferences.nib
cd ..

cd Japanese.lproj
rm -rf Preferences*.nib
cvs update -d Preferences.nib
nibtool --use-oids --localizable-strings Preferences.nib > previous.strings
nibtool --use-oids --dictionary previous.strings -W Preferences_new.nib ../English.lproj/Preferences.nib
mv Preferences.nib Preferences_old.nib
mv Preferences_new.nib Preferences.nib
mv Preferences_old.nib/CVS Preferences.nib
cd ..

cd Dutch.lproj
rm -rf Preferences*.nib
cvs update -d Preferences.nib
nibtool --use-oids --localizable-strings Preferences.nib > previous.strings
nibtool --use-oids --dictionary previous.strings -W Preferences_new.nib ../English.lproj/Preferences.nib
mv Preferences.nib Preferences_old.nib
mv Preferences_new.nib Preferences.nib
mv Preferences_old.nib/CVS Preferences.nib
cd ..

cd Italian.lproj
rm -rf Preferences*.nib
cvs update -d Preferences.nib
nibtool --use-oids --localizable-strings Preferences.nib > previous.strings
nibtool --use-oids --dictionary previous.strings -W Preferences_new.nib ../English.lproj/Preferences.nib
mv Preferences.nib Preferences_old.nib
mv Preferences_new.nib Preferences.nib
mv Preferences_old.nib/CVS Preferences.nib
cd ..

cd Spanish.lproj
rm -rf Preferences*.nib
cvs update -d Preferences.nib
nibtool --use-oids --localizable-strings Preferences.nib > previous.strings
nibtool --use-oids --dictionary previous.strings -W Preferences_new.nib ../English.lproj/Preferences.nib
mv Preferences.nib Preferences_old.nib
mv Preferences_new.nib Preferences.nib
mv Preferences_old.nib/CVS Preferences.nib
cd ..

