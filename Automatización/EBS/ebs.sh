aws elasticbeanstalk create-application-version \
    --application-name green-blue \
    --version-label v1 \
    --source-bundle S3Bucket=amzn-s3-demo-bucket,S3Key=green-blue.zip

    # Para crear una versión de aplicación desde CLI aparentemente
    # no se puede subir el fichero .zip directamente. Hay que subir
    # el fichero a un S3 primero y enlazarlo con --source-bundle

aws elasticbeanstalk create-environment \
    --application-name green-blue \
    --solution-stack-name "64bit Amazon Linux 2023 v4.1.0 running PHP 8.4" \
    --version-label v1 \
    --environment-name green-blue-env \
    --option-settings file://./options.txt
    #--cname-prefix my-cname \



aws elasticbeanstalk describe-environments \
    --environment-names green-blue-env