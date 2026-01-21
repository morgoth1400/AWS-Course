import boto3
import time

REGIONS = ["us-east-1", "us-west-2"]
KEY_NAME = "vockey"
INSTANCE_TYPE = "t2.micro"

AMI = {
    "us-east-1": "ami-0c02fb55956c7d316",
    "us-west-2": "ami-0892d3c7ee96c0bf7"
}

sts = boto3.client("sts")
ACCOUNT_ID = sts.get_caller_identity()["Account"]

def wait_state(check_fn, desc):
    while True:
        state = check_fn()
        print(f"    {desc}: {state}")
        if state == "available":
            return
        time.sleep(10)

def main():
    region_data = {}

    for region in REGIONS:
        print(f"\n=== REGIÓN {region} ===")
        ec2 = boto3.client("ec2", region_name=region)

        # TGW
        tgw = ec2.create_transit_gateway(
            Description=f"TGW-{region}"
        )
        tgw_id = tgw["TransitGateway"]["TransitGatewayId"]
        print(f"[+] TGW creado: {tgw_id}")

        wait_state(
            lambda: ec2.describe_transit_gateways(
                TransitGatewayIds=[tgw_id]
            )["TransitGateways"][0]["State"],
            f"TGW {tgw_id}"
        )

        vpcs = []

        for i in range(2):
            vpc = ec2.create_vpc(CidrBlock=f"10.{i}.0.0/16")["Vpc"]["VpcId"]
            ec2.modify_vpc_attribute(VpcId=vpc, EnableDnsSupport={"Value": True})
            ec2.modify_vpc_attribute(VpcId=vpc, EnableDnsHostnames={"Value": True})

            subnet = ec2.create_subnet(
                VpcId=vpc,
                CidrBlock=f"10.{i}.1.0/24"
            )["Subnet"]["SubnetId"]

            igw = ec2.create_internet_gateway()["InternetGateway"]["InternetGatewayId"]
            ec2.attach_internet_gateway(VpcId=vpc, InternetGatewayId=igw)

            rt = ec2.create_route_table(VpcId=vpc)["RouteTable"]["RouteTableId"]
            ec2.create_route(
                RouteTableId=rt,
                DestinationCidrBlock="0.0.0.0/0",
                GatewayId=igw
            )
            ec2.associate_route_table(RouteTableId=rt, SubnetId=subnet)

            sg = ec2.create_security_group(
                GroupName=f"gs-{region}-{i}",
                Description="SSH + ICMP",
                VpcId=vpc
            )["GroupId"]

            ec2.authorize_security_group_ingress(
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

            instance = ec2.run_instances(
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
                }]
            )["Instances"][0]

            ec2.get_waiter("instance_running").wait(
                InstanceIds=[instance["InstanceId"]]
            )

            attach = ec2.create_transit_gateway_vpc_attachment(
                TransitGatewayId=tgw_id,
                VpcId=vpc,
                SubnetIds=[subnet]
            )

            attach_id = attach["TransitGatewayVpcAttachment"]["TransitGatewayAttachmentId"]

            wait_state(
                lambda: ec2.describe_transit_gateway_attachments(
                    TransitGatewayAttachmentIds=[attach_id]
                )["TransitGatewayAttachments"][0]["State"],
                f"Attachment {attach_id}"
            )

            vpcs.append(vpc)

        region_data[region] = {"ec2": ec2, "tgw": tgw_id}

    print("\n=== PEERING ENTRE REGIONES ===")

    ec2_east = region_data["us-east-1"]["ec2"]
    ec2_west = region_data["us-west-2"]["ec2"]

    peer = ec2_east.create_transit_gateway_peering_attachment(
        TransitGatewayId=region_data["us-east-1"]["tgw"],
        PeerTransitGatewayId=region_data["us-west-2"]["tgw"],
        PeerAccountId=ACCOUNT_ID,
        PeerRegion="us-west-2"
    )

    peer_id = peer["TransitGatewayPeeringAttachment"]["TransitGatewayAttachmentId"]
    print(f"[+] Peering creado: {peer_id}")

    ec2_west.accept_transit_gateway_peering_attachment(
        TransitGatewayAttachmentId=peer_id
    )

    print("\n✔ ESCENARIO COMPLETO CON TGW + PEERING")

if __name__ == "__main__":
    main()
