
#############################################
####                                     ####
####    CRAECIÓN DE UNA INSTANCIA EC2    ####
####                                     ####
#############################################

    ########################
    ###     CREACIÓN     ###
    ########################
    EC2_ID=$(aws ec2 run-instances \
        --image-id ami-0ecb62995f68bb549 \
        --instance-type t2.micro \
        --subnet-id subnet-0023a1097791d492d \
        --security-group-ids sg-08f7afce10fd1f46c \
        --count 1 \
        --key-name vockey \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Daniel-Instance-PRIVATE}]' \
        --query 'Instances[*].InstanceId' --output text)

    ########################################################
    ###     ESPERAMOS HASTA QUE SE CREE LA INSTANCIA     ###
    ########################################################
    aws ec2 wait instance-running \
        --instance-ids $EC2_ID
            # Con este comando le indicamos que esperemos hasta que la instancia se cree.

    ################################
    ###     IMPRESIÓN DEL ID     ###
    ################################
    echo "-------------------------------------------------------------"
    echo "• La ID de la instancia es :" $EC2_ID