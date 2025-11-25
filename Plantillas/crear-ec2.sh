#!/bin/bash

#### CREACIÓN VPC

    VPC_ID=$(aws ec2 create-vpc --cidr-block 192.168.0.0/16 \
        --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=Hector-VPC}]' \
        --query Vpc.VpcId --output text)
            # Asignamos la dirección IP y sacamos una query con la ID.

    echo "La ID de la VPC es:" $VPC_ID


#### CREACIÓN PUERTA DE ENLACE

    GW_ID=$(aws ec2 create-internet-gateway \
        --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=Hector-GW}]' \
        --region us-east-1\
        --query InternetGateway.InternetGatewayId --output text)

    ### ASIGNACIÓN DE LA PUERTO DE ENLACE A LA VPC
    aws ec2 attach-internet-gateway \
        --internet-gateway-id $GW_ID \
        --vpc-id $VPC_ID

    ### HABILITAMOS EL DNS EN LA VPC
    aws ec2 modify-vpc-attribute \
        --vpc-id $VPC_ID \
        --enable-dns-hostnames "{\"Value\":true}"

    echo "-------------------------------------------------------------"
    echo "• La ID de la puerta de enlace es :" $GW_ID


####    CREACIÓN SUBRED    ####

    SUB_ID=$(aws ec2 create-subnet \
        --vpc-id $VPC_ID \
        --cidr-block 192.168.0.0/20 \
        --availability-zone us-east-1a \
        --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Hector-Subred}]' \
        --query Subnet.SubnetId --output text)

    echo "-------------------------------------------------------------"
    echo "La ID de la subred es :" $SUB_ID

#### CREACIÓN TABLA DE ENRUTAMIENTO

    RT_ID=$(aws ec2 create-route-table \
        --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Hector-RT}]'\
        --vpc-id $VPC_ID --query RouteTable.RouteTableId --output text) >/dev/null

    ### ASOCIACIÓN DE LA TABLA DE ENRUTAMIENTO A UNA SUBRED
    ATTACH_STATE=$(aws ec2 associate-route-table --route-table-id $RT_ID --subnet-id $SUB_ID) >/dev/null
    ATTACH_STATE=$(echo $ATTACH_STATE | cut -d',' -f2 | cut -d':' -f3 | cut -d'"' -f2)>/dev/null


        echo "-------------------------------------------------------------"
        echo "Asociación de la tabla de enrutamiento" $RT_ID "con la subred" $SUB_ID". Estado: "$ATTACH_STATE

    ### CREACIÓN DE RUTA 0.0.0.0/0
    aws ec2 create-route --route-table-id $RT_ID \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id $GW_ID
            # Indicamos que todo el tráfico IPv4 vaya por el Gateway.

    echo "-------------------------------------------------------------"
    echo "• La ID de la tabla de enrutamiento es : " $RT_ID


#### CREACIÓN  GRUPO DE SEGURIDAD

    SG_ID=$(aws ec2 create-security-group --group-name My-SG \
        --description "Mi grupito de seguridad - 22P" \
        --vpc-id $VPC_ID \
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

    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 > /dev/null
            # Habilitamos el puerto: 80.

    aws ec2 authorize-security-group-ingress \
        --group-id $SG_ID \
        --protocol tcp \
        --port 443 \
        --cidr 0.0.0.0/0 > /dev/null
            # Habilitamos el puerto: 443.

    ### HABILITAMOS LA ASIGNACIÓN DE DIRECCIÓN IPv4 PÚBLICA
    aws ec2 modify-subnet-attribute --subnet-id $SUB_ID --map-public-ip-on-launch

    echo "-------------------------------------------------------------"
    echo "• La ID de el grupo de seguridad es :" $SG_ID
    echo "• El ARN de el grupo de seguridad es :" $SG_ID_ARN

####    CRAECIÓN DE UNA INSTANCIA EC2

    EC2_ID=$(aws ec2 run-instances \
        --image-id ami-0ecb62995f68bb549 \
        --instance-type t2.micro \
        --subnet-id $SUB_ID \
        --security-group-ids $SG_ID \
        --associate-public-ip-address \
        --private-ip-address 192.168.0.100 \
        --count 1 \
        --key-name vockey \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Hector-Instance}]' \
        --query 'Instances[*].InstanceId' --output text)

    ### ESPERAMOS HASTA QUE SE CREE LA INSTANCIA
    aws ec2 wait instance-running \
        --instance-ids $EC2_ID
            # Con este comando le indicamos que esperemos hasta que la instancia se cree.

    echo "-------------------------------------------------------------"
    echo "• La ID de la instancia es :" $EC2_ID

    ## ASIGNACIÓN POSTERIOR - GRUPO DE SEGURIDAD (OPCIONAL)
    # aws ec2 modify-instance-attribute \
    #     --instance-id $EC2_ID \
    #     --groups $SG_ID
                # Es únicamente en caso de no haber indicado previamente el grupo de
                    # de seguridad durante la creación de la instancia.