import boto3
import time
from botocore.exceptions import ClientError

# -----------------------------
# CONFIGURACIÓN
# -----------------------------
REGIONS = {
    "nv": {
        "name": "us-east-1",
        "vpc_cidr": "10.0.0.0/16",
        "public_subnet": "10.0.1.0/24",
        "az": "us-east-1a",
        "key": "vockey"
    },
    "or": {
        "name": "us-west-2",
        "vpc_cidr": "10.1.0.0/16",
        "public_subnet": "10.1.1.0/24",
        "az": "us-west-2a",
        "key": "vockey"
    }
}

AMI = {
    "us-east-1": "ami-0c02fb55956c7d316",
    "us-west-2": "ami-0c02fb55956c7d316"
}

resources = {}

# -----------------------------
# CLIENTE
# -----------------------------
def ec2(region):
    return boto3.client("ec2", region_name=region)

# -----------------------------
# LIMPIEZA
# -----------------------------
def cleanup(region_cfg):
    client = ec2(region_cfg["name"])

    # ---- PEERING ----
    for p in client.describe_vpc_peering_connections()["VpcPeeringConnections"]:
        try:
            client.delete_vpc_peering_connection(
                VpcPeeringConnectionId=p["VpcPeeringConnectionId"]
            )
        except ClientError:
            pass

    time.sleep(5)

    # ---- VPCS ----
    for vpc in client.describe_vpcs()["Vpcs"]:
        if vpc["CidrBlock"] != region_cfg["vpc_cidr"]:
            continue

        vpc_id = vpc["VpcId"]
        print(f"[CLEANUP] Eliminando VPC {vpc_id}")

        # EC2
        res = client.describe_instances(
            Filters=[{"Name": "vpc-id", "Values": [vpc_id]}]
        )
        instance_ids = [
            i["InstanceId"]
            for r in res["Reservations"]
            for i in r["Instances"]
        ]

        if instance_ids:
            client.terminate_instances(InstanceIds=instance_ids)
            client.get_waiter("instance_terminated").wait(
                InstanceIds=instance_ids
            )

        time.sleep(5)

        # ENI
        enis = client.describe_network_interfaces(
            Filters=[{"Name": "vpc-id", "Values": [vpc_id]}]
        )["NetworkInterfaces"]

        for eni in enis:
            try:
                client.delete_network_interface(
                    NetworkInterfaceId=eni["NetworkInterfaceId"]
                )
            except ClientError:
                pass

        time.sleep(5)

        # ROUTE TABLES
        for rt in client.describe_route_tables(
            Filters=[{"Name": "vpc-id", "Values": [vpc_id]}]
        )["RouteTables"]:

            for assoc in rt.get("Associations", []):
                if not assoc.get("Main"):
                    client.disassociate_route_table(
                        AssociationId=assoc["RouteTableAssociationId"]
                    )

            if not any(a.get("Main") for a in rt.get("Associations", [])):
                try:
                    client.delete_route_table(RouteTableId=rt["RouteTableId"])
                except ClientError:
                    pass

        time.sleep(5)

        # SUBNETS
        for s in client.describe_subnets(
            Filters=[{"Name": "vpc-id", "Values": [vpc_id]}]
        )["Subnets"]:
            client.delete_subnet(SubnetId=s["SubnetId"])

        time.sleep(5)

        # IGW
        for igw in client.describe_internet_gateways(
            Filters=[{"Name": "attachment.vpc-id", "Values": [vpc_id]}]
        )["InternetGateways"]:
            client.detach_internet_gateway(
                InternetGatewayId=igw["InternetGatewayId"],
                VpcId=vpc_id
            )
            client.delete_internet_gateway(
                InternetGatewayId=igw["InternetGatewayId"]
            )

        time.sleep(5)

        # SECURITY GROUPS
        for sg in client.describe_security_groups(
            Filters=[{"Name": "vpc-id", "Values": [vpc_id]}]
        )["SecurityGroups"]:
            if sg["GroupName"] != "default":
                try:
                    client.delete_security_group(GroupId=sg["GroupId"])
                except ClientError:
                    pass

        time.sleep(10)

        # DELETE VPC (reintentos)
        for _ in range(6):
            try:
                client.delete_vpc(VpcId=vpc_id)
                print(f"[CLEANUP] VPC {vpc_id} eliminada")
                break
            except ClientError:
                time.sleep(10)

# -----------------------------
# LIMPIEZA PREVIA
# -----------------------------
#for cfg in REGIONS.values():
#    cleanup(cfg)

# -----------------------------
# CREACIÓN
# -----------------------------
for tag, cfg in REGIONS.items():
    client = ec2(cfg["name"])
    resources[tag] = {}

    vpc = client.create_vpc(CidrBlock=cfg["vpc_cidr"])["Vpc"]["VpcId"]
    client.modify_vpc_attribute(VpcId=vpc, EnableDnsSupport={"Value": True})
    client.modify_vpc_attribute(VpcId=vpc, EnableDnsHostnames={"Value": True})

    igw = client.create_internet_gateway()["InternetGateway"]["InternetGatewayId"]
    client.attach_internet_gateway(InternetGatewayId=igw, VpcId=vpc)

    subnet = client.create_subnet(
        VpcId=vpc,
        CidrBlock=cfg["public_subnet"],
        AvailabilityZone=cfg["az"]
    )["Subnet"]["SubnetId"]

    client.modify_subnet_attribute(
        SubnetId=subnet,
        MapPublicIpOnLaunch={"Value": True}
    )

    rt = client.create_route_table(VpcId=vpc)["RouteTable"]["RouteTableId"]
    client.create_route(
        RouteTableId=rt,
        DestinationCidrBlock="0.0.0.0/0",
        GatewayId=igw
    )
    client.associate_route_table(RouteTableId=rt, SubnetId=subnet)

    sg = client.create_security_group(
        GroupName=f"exam-sg-{tag}",
        Description="SSH + ICMP",
        VpcId=vpc
    )["GroupId"]

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
                "IpRanges": [{"CidrIp": REGIONS["nv"]["vpc_cidr"]},
                             {"CidrIp": REGIONS["or"]["vpc_cidr"]}]
            }
        ]
    )

    instance = client.run_instances(
        ImageId=AMI[cfg["name"]],
        InstanceType="t2.micro",
        MinCount=1,
        MaxCount=1,
        KeyName=cfg["key"],
        SubnetId=subnet,
        SecurityGroupIds=[sg]
    )["Instances"][0]

    client.get_waiter("instance_running").wait(
        InstanceIds=[instance["InstanceId"]]
    )

    dns = client.describe_instances(
        InstanceIds=[instance["InstanceId"]]
    )["Reservations"][0]["Instances"][0]["PublicDnsName"]

    resources[tag]["vpc"] = vpc
    resources[tag]["rt"] = rt
    resources[tag]["dns"] = dns

# -----------------------------
# PEERING + RUTAS
# -----------------------------
nv = ec2("us-east-1")
or_ = ec2("us-west-2")

peer = nv.create_vpc_peering_connection(
    VpcId=resources["nv"]["vpc"],
    PeerVpcId=resources["or"]["vpc"],
    PeerRegion="us-west-2"
)["VpcPeeringConnection"]["VpcPeeringConnectionId"]

time.sleep(5)
or_.accept_vpc_peering_connection(VpcPeeringConnectionId=peer)
time.sleep(5)

for a, b in [("nv", "or"), ("or", "nv")]:
    ec2(REGIONS[a]["name"]).create_route(
        RouteTableId=resources[a]["rt"],
        DestinationCidrBlock=REGIONS[b]["vpc_cidr"],
        VpcPeeringConnectionId=peer
    )

# -----------------------------
# RESULTADO
# -----------------------------
print("\n=== DNS PÚBLICOS ===")
print("North Virginia:", resources["nv"]["dns"])
print("Oregón:", resources["or"]["dns"])

