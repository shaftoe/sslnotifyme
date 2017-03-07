#!/bin/bash
set -e

readonly bucket='sslnotifyme-frontend'
readonly files="$(ls *js *html *gif *ico *.txt *.xml)"

aws --version

echo 'Using sslnotifyme profile'
for file in $files; do
    aws --profile sslnotifyme s3 cp $file "s3://${bucket}/"
done

echo; echo "https://sslnotify.me/"
