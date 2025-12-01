#!/bin/bash
SG_ID=$(aws ec2 create-security-group --group-name My-SG \
    --description "GS-22" \
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


aws ec2 run-instances \
    --image-id ami-0ecb62995f68bb549 \
    --instance-type t2.micro \
    --associate-public-ip-address \
    --count 1 \
    --key-name vockey \
    --security-group-ids $SG_ID \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Dani-Ubuntu}]' \
    --query 'Instances[*].InstanceId' --output text

        #--subnet-id $SUB_ID \
        #--security-group-ids $SG_ID \
        #--private-ip-address 192.168.0.100 \

aws ec2 describe-instances \
    --instance-ids i-0d0d272b82d555cf5 \
    --query "Reservations[*].Instances[*].PublicIpAddress" --output text