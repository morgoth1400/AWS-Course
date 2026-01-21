import boto3
import time

REGION_1 = "us-east-1"
REGION_2 = "us-west-2"
KEY_NAME = "vockey"
INSTANCE_TYPE = "t2.micro"

AMI = {
    "us-east-1": "ami-0c02fb55956c7d316",
    "us-west-2": "ami-0892d3c7ee96c0bf7"
}

VPCS = {
    REGION_1: ["10.0.0.0/16", "10.1.0.0/16"],
    REGION_2: ["10.2.0.0/16"]
}

def ec2(region):
    return boto3.client("ec2", region_name=region)

def wait_tgw_available(ec2c, tgw_id):
    while True:
        state = ec2c.describe_transit_gateways(
            TransitGatewayIds=[tgw_id]
        )["TransitGateways"][0]["State"]
        print(f"    TGW {tgw_id} → {state}")
        if state == "available":
            return
        time.sleep(10)

def wait_attach_available(ec2c, attach_id):
    while True:
        state = ec2c.describe_transit_gateway_attachments(
            TransitGatewayAttachmentIds=[attach_id]
        )["TransitGatewayAttachments"][0]["State"]
        print(f"    Attachment {attach_id} → {state}")
        if state == "available":
            return
        time.sleep(10)

def create_vpc_and_attach(region, tgw_id, cidr, index):
    client = ec2(region)

    print(f"\n[+] Creando VPC {cidr} en {region}")
    vpc = client.create_vpc(CidrBlock=cidr)["Vpc"]["VpcId"]
    client.create_tags(Resources=[vpc], Tags=[{"Key": "Name", "Value": f"VPC-{region}-{index}"}])

    client.modify_vpc_attribute(VpcId=vpc, EnableDnsSupport={"Value": True})
    client.modify_vpc_attribute(VpcId=vpc, EnableDnsHostnames={"Value": True})
    print(f"    VPC creada: {vpc}")

    subnet_cidr = cidr.replace("/16", "/24")
    subnet = client.create_subnet(
        VpcId=vpc,
        CidrBlock=subnet_cidr
    )["Subnet"]["SubnetId"]
    client.create_tags(Resources=[subnet], Tags=[{"Key": "Name", "Value": f"Subnet-{region}-{index}"}])
    print(f"    Subnet creada: {subnet} ({subnet_cidr})")

    sg = client.create_security_group(
        GroupName=f"sec-{region}-{index}",
        Description="SSH + ICMP",
        VpcId=vpc
    )["GroupId"]
    print(f"    Security Group creado: {sg}")

    client.authorize_security_group_ingress(
        GroupId=sg,
        IpPermissions=[
            {
                "IpProtocol": "tcp",
                "FromPort": 22,
                "ToPort": 22,
                "IpRanges": [{"CidrIp": "0.0.0.0/0"}]
            },
            {
                "IpProtocol": "icmp",
                "FromPort": -1,
                "ToPort": -1,
                "IpRanges": [{"CidrIp": "0.0.0.0/0"}]
            }
        ]
    )
    print("    Reglas SSH + ICMP añadidas")

    print("    Lanzando EC2…")
    instance = client.run_instances(
        ImageId=AMI[region],
        InstanceType=INSTANCE_TYPE,
        KeyName=KEY_NAME,
        MinCount=1,
        MaxCount=1,
        NetworkInterfaces=[{
            "SubnetId": subnet,
            "DeviceIndex": 0,
            "AssociatePublicIpAddress": True,
            "Groups": [sg]
        }],
        TagSpecifications=[{
            "ResourceType": "instance",
            "Tags": [{"Key": "Name", "Value": f"EC2-{region}-{index}"}]
        }]
    )

    instance_id = instance["Instances"][0]["InstanceId"]
    client.get_waiter("instance_running").wait(InstanceIds=[instance_id])
    print(f"    EC2 creada y corriendo: {instance_id}")

    print("    Creando attachment al TGW…")
    attach = client.create_transit_gateway_vpc_attachment(
        TransitGatewayId=tgw_id,
        VpcId=vpc,
        SubnetIds=[subnet]
    )

    attach_id = attach["TransitGatewayVpcAttachment"]["TransitGatewayAttachmentId"]
    wait_attach_available(client, attach_id)
    print(f"    VPC {vpc} conectada al TGW")

def main():
    ec2_r1 = ec2(REGION_1)
    ec2_r2 = ec2(REGION_2)

    print("\n=== CREANDO TGW EN us-east-1 ===")
    tgw_r1 = ec2_r1.create_transit_gateway(
        Description="TGW-us-east-1",
        TagSpecifications=[{
            "ResourceType": "transit-gateway",
            "Tags": [{"Key": "Name", "Value": "TGW-us-east-1"}]
        }]
    )["TransitGateway"]["TransitGatewayId"]

    wait_tgw_available(ec2_r1, tgw_r1)

    print("\n=== CREANDO TGW EN us-west-2 ===")
    tgw_r2 = ec2_r2.create_transit_gateway(
        Description="TGW-us-west-2",
        TagSpecifications=[{
            "ResourceType": "transit-gateway",
            "Tags": [{"Key": "Name", "Value": "TGW-us-west-2"}]
        }]
    )["TransitGateway"]["TransitGatewayId"]

    wait_tgw_available(ec2_r2, tgw_r2)

    print("\n=== CREANDO VPCS + EC2 ===")
    for i, cidr in enumerate(VPCS[REGION_1], 1):
        create_vpc_and_attach(REGION_1, tgw_r1, cidr, i)

    for i, cidr in enumerate(VPCS[REGION_2], 1):
        create_vpc_and_attach(REGION_2, tgw_r2, cidr, i)

    print("\n=== CREANDO PEERING ENTRE TGW ===")
    sts = boto3.client("sts")
    account_id = sts.get_caller_identity()["Account"]

    peer = ec2_r1.create_transit_gateway_peering_attachment(
        TransitGatewayId=tgw_r1,
        PeerTransitGatewayId=tgw_r2,
        PeerAccountId=account_id,
        PeerRegion=REGION_2
    )

    peer_id = peer["TransitGatewayPeeringAttachment"]["TransitGatewayAttachmentId"]
    print(f"[+] Peering creado: {peer_id}")

    time.sleep(30)

    ec2_r2.accept_transit_gateway_peering_attachment(
        TransitGatewayAttachmentId=peer_id
    )

    print("\n✔ ESCENARIO COMPLETO DESPLEGADO CORRECTAMENTE")

if __name__ == "__main__":
    main()
