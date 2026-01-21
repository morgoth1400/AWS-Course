import pymysql
import time

def run_test(host):
    for i in range(30):
        try:
            conn = pymysql.connect(
                host="rds-proxy-daniel.cnrguvo7mo7i.us-east-1.rds.amazonaws.com",
                user="admin",
                password="c[$[T694DP62huoI$vkz8cwq!8U:",
                database="pru",
                connect_timeout=3
            )
            with conn.cursor() as cur:
                cur.execute("SELECT 1;")
                print(f"[{i}] OK")
            conn.close()
        except Exception as e:
            print(f"[{i}] ERROR: {e}")
        time.sleep(1)

# Endpoint directo del RDS
run_test("rds-proxy-daniel.cnrguvo7mo7i.us-east-1.rds.amazonaws.com")