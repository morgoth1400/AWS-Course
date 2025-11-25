import time
import random
import threading
import mysql.connector
from concurrent.futures import ThreadPoolExecutor

AURORA_CONFIG = {
    "host": "aurora-a-instance-1.cls2euu6wkxd.us-east-1.rds.amazonaws.com",
    "user": "admin",
    "password": "juande123",
    "database": "prueba",
    "port": 3306
}

# Cantidad de hilos concurrentes
NUM_THREADS = 50

# Tiempo total de prueba en segundos
TEST_DURATION = 300  # 5 minutos


def run_queries(thread_id):
    """Ejecuta consultas de estrés hasta que acabe TEST_DURATION."""
    conn = mysql.connector.connect(**AURORA_CONFIG)
    cursor = conn.cursor()

    start = time.time()

    while time.time() - start < TEST_DURATION:
        try:
            # Consulta pesada simulada
            cursor.execute("SELECT SLEEP(0.1), RAND(), BENCHMARK(5000000, RAND());")
            cursor.fetchall()

            # Consulta aleatoria opcional
            num = random.randint(1, 10)
            cursor.execute(f"SELECT {num} * {num};")
            cursor.fetchall()

        except Exception as e:
            print(f"[Thread {thread_id}] Error: {e}")
            time.sleep(1)

    cursor.close()
    conn.close()
    print(f"[Thread {thread_id}] finalizado.")


def main():
    print("Iniciando estrés contra Aurora...")
    with ThreadPoolExecutor(max_workers=NUM_THREADS) as executor:
        for i in range(NUM_THREADS):
            executor.submit(run_queries, i)

    print("Carga completada.")


if __name__ == "__main__":
    main()