
aws elasticbeanstalk create-application \
    --application-name blue
aws elasticbeanstalk create-application-version \
    --application-name blue \
    --version-label v1 \
    --source-bundle S3Bucket=blue-green-morgoth1400,S3Key=indexB.zip

    # Para crear una versión de aplicación desde CLI aparentemente
    # no se puede subir el fichero .zip directamente. Hay que subir
    # el fichero a un S3 primero y enlazarlo con --source-bundle

aws elasticbeanstalk create-environment \
    --cname-prefix blue-morgoth1400 \
    --application-name blue \
    --environment-name blue-env \
    --solution-stack-name "64bit Amazon Linux 2023 v4.8.0 running PHP 8.4" \
    --version-label v1 \
    --option-settings file://./options.txt


aws elasticbeanstalk create-application-version \
  --application-name blue \
  --version-label v2 \
  --source-bundle S3Bucket=blue-green-morgoth1400,S3Key=indexG.zip

aws elasticbeanstalk create-environment \
    --cname-prefix green-morgoth1400 \
    --application-name blue \
    --environment-name green-env \
    --solution-stack-name "64bit Amazon Linux 2023 v4.8.0 running PHP 8.4" \
    --version-label v2 \
    --option-settings file://./options.txt

aws elasticbeanstalk swap-environment-cnames \
  --source-environment-name blue-env \
  --destination-environment-name green-env



aws elasticbeanstalk describe-environments \
    --environment-names blue-env