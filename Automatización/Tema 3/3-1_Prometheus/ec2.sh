#!/bin/bash
#!/bin/bash
SG_ID=$(aws ec2 create-security-group --group-name GS-22 \
    --description "AAAGS-22" \
    --output text)

    ### SEPARAMOS EN DOS VARIABLES LOS DOS VALORES
SG_ID_ARN=$(echo $SG_ID | cut -d' ' -f2)
        # Obtenemos el ARN de el grupo de seguridad.
SG_ID=$(echo $SG_ID | cut -d' ' -f1)
        # Obtenemos el ID de el grupo de seguridad.

    ### HABILITAMOS LOS PUERTOS EN EL GRUPO DE SEGURIDAD
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 > /dev/null
            # Habilitamos el puerto: 22. Con el /dev/null indicamos que no
                # muestre información.

SG_ID_P=$(aws ec2 create-security-group --group-name GS-PROMETHEUS \
    --description "Prometheus" \
    --output text)

    ### SEPARAMOS EN DOS VARIABLES LOS DOS VALORES
SG_ID_P_ARN=$(echo $SG_ID_P | cut -d' ' -f2)
        # Obtenemos el ARN de el grupo de seguridad.
SG_ID_P=$(echo $SG_ID_P | cut -d' ' -f1)
        # Obtenemos el ID de el grupo de seguridad.

    ### HABILITAMOS LOS PUERTOS EN EL GRUPO DE SEGURIDAD
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID_P \
    --protocol tcp \
    --port 9100 \
    --cidr 0.0.0.0/0 > /dev/null

aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID_P \
    --protocol tcp \
    --port 9090 \
    --cidr 0.0.0.0/0 > /dev/null
            # Habilitamos el puerto: 22. Con el /dev/null indicamos que no
                # muestre información.

EC2_ID=$(aws ec2 run-instances \
    --image-id ami-0fa3fe0fa7920f68e \
    --instance-type t2.micro \
    --associate-public-ip-address \
    --count 1 \
    --key-name vockey \
    --security-group-ids $SG_ID \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ec2_a}]' \
    --user-data file://./userdataE.txt \
    --query 'Instances[*].InstanceId' --output text)

        #--subnet-id $SUB_ID \
        #--security-group-ids $SG_ID \
        #--private-ip-address 192.168.0.100 \

aws ec2 describe-instances \
    --instance-ids i-04de52bb44e0a2c88 \
    --query "Reservations[*].Instances[*].PublicIpAddress" --output text

P_ID=$(aws ec2 run-instances \
    --image-id ami-0fa3fe0fa7920f68e \
    --instance-type t2.micro \
    --associate-public-ip-address \
    --count 1 \
    --key-name vockey \
    --security-group-ids $SG_ID_P \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Prometheus}]' \
    --user-data file://.userdataP.txt \
    --query 'Instances[*].InstanceId' --output text)