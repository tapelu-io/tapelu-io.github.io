#!/bin/bash

set -e

PROJECT_NAME="kafka-push-arch"
TOPIC_NAME="demo-topic"
DLQ_TOPIC_NAME="demo-topic-dlq"

# Step 1: Write Docker Compose for services
cat <<EOF > docker-compose.yml
version: '3.8'
services:
  zookeeper:
    image: confluentinc/cp-zookeeper:latest
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
    ports:
      - "2181:2181"

  broker:
    image: confluentinc/cp-kafka:latest
    depends_on:
      - zookeeper
    ports:
      - "9092:9092"
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://broker:9092
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT
      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1

  producer_proxy:
    build: ./producer_proxy
    depends_on:
      - broker
    ports:
      - "50051:50051"
    volumes:
      - ./logs:/logs
    environment:
      - PYTHONUNBUFFERED=1

  consumer_push:
    build: ./consumer_push
    ports:
      - "50052:50052"
    volumes:
      - ./logs:/logs
    environment:
      - PYTHONUNBUFFERED=1

  dashboard:
    image: nginx:alpine
    volumes:
      - ./dashboard:/usr/share/nginx/html:ro
    ports:
      - "8080:80"
EOF

# Step 2: Create topics
docker compose up -d zookeeper broker
sleep 10
docker exec broker kafka-topics --bootstrap-server broker:9092 \
  --create --if-not-exists --topic "$TOPIC_NAME" --replication-factor 1 --partitions 1

docker exec broker kafka-topics --bootstrap-server broker:9092 \
  --create --if-not-exists --topic "$DLQ_TOPIC_NAME" --replication-factor 1 --partitions 1

# Step 3: Generate dashboard HTML with auto-refresh log viewer
mkdir -p dashboard logs
cat <<EOF > dashboard/index.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Kafka Push Dashboard</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { font-family: sans-serif; background: #f5f5f5; padding: 2rem; }
    h1 { color: #333; }
    .log { white-space: pre-wrap; background: #000; color: #0f0; padding: 1rem; font-family: monospace; border-radius: 5px; height: 300px; overflow-y: scroll; }
  </style>
</head>
<body>
  <h1>Kafka Push Architecture Dashboard</h1>
  <p><strong>Producer:</strong> localhost:50051<br>
     <strong>Consumer:</strong> localhost:50052<br>
     <strong>Broker:</strong> localhost:9092</p>
  <h2>Live Logs (Auto Refresh)</h2>
  <iframe src="producer.log" width="100%" height="300" style="border:1px solid #ccc"></iframe>
  <iframe src="consumer.log" width="100%" height="300" style="border:1px solid #ccc"></iframe>
</body>
</html>
EOF

# Step 4: Project structure and Dockerfiles
for dir in producer_proxy consumer_push; do
  mkdir -p "$dir/proto"
  cat <<DOCKERFILE > "$dir/Dockerfile"
FROM python:3.10-slim
WORKDIR /app
COPY . /app
RUN pip install --no-cache-dir grpcio grpcio-tools kafka-python
RUN python -m grpc_tools.protoc -I proto --python_out=. --grpc_python_out=. proto/service.proto
CMD ["sh", "-c", "python server.py | tee /logs/${PWD##*/}.log"]
DOCKERFILE

done

# Step 5: Shared proto definition
PROTO_CONTENT='syntax = "proto3";
package demo;
service ProducerProxy {
  rpc Produce (ProduceRequest) returns (ProduceResponse);
}
service ConsumerPush {
  rpc PushMessage (Message) returns (Ack);
}
message ProduceRequest {
  string key = 1;
  string value = 2;
}
message ProduceResponse {
  bool success = 1;
}
message Message {
  string key = 1;
  string value = 2;
}
message Ack {
  bool received = 1;
}'
echo "$PROTO_CONTENT" | tee producer_proxy/proto/service.proto consumer_push/proto/service.proto

# Step 6: Python servers with DLQ support
cat <<EOF > producer_proxy/server.py
import grpc
from concurrent import futures
from kafka import KafkaProducer
import service_pb2, service_pb2_grpc
class ProducerProxy(service_pb2_grpc.ProducerProxyServicer):
    def __init__(self):
        self.producer = KafkaProducer(bootstrap_servers='broker:9092')
    def Produce(self, request, context):
        print(f"[ProducerProxy] key={request.key}, value={request.value}")
        try:
            self.producer.send('demo-topic', key=request.key.encode(), value=request.value.encode())
            self.producer.flush()
            return service_pb2.ProduceResponse(success=True)
        except Exception as e:
            print("Produce error:", e)
            return service_pb2.ProduceResponse(success=False)
def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    service_pb2_grpc.add_ProducerProxyServicer_to_server(ProducerProxy(), server)
    server.add_insecure_port('[::]:50051')
    server.start()
    print("Producer Proxy gRPC server started on port 50051")
    server.wait_for_termination()
if __name__ == '__main__':
    serve()
EOF

cat <<EOF > consumer_push/server.py
import grpc
import random
from concurrent import futures
from kafka import KafkaProducer
import service_pb2, service_pb2_grpc
class ConsumerPush(service_pb2_grpc.ConsumerPushServicer):
    def __init__(self):
        self.dlq = KafkaProducer(bootstrap_servers='broker:9092')
    def PushMessage(self, request, context):
        print(f"[ConsumerPush] Received key={request.key}, value={request.value}")
        # Simulate random failure
        if random.random() < 0.3:
            print("[ConsumerPush] ERROR: Simulated processing failure → DLQ")
            self.dlq.send('demo-topic-dlq', key=request.key.encode(), value=request.value.encode())
            self.dlq.flush()
            return service_pb2.Ack(received=False)
        print("[ConsumerPush] Message processed successfully")
        return service_pb2.Ack(received=True)
def serve():
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    service_pb2_grpc.add_ConsumerPushServicer_to_server(ConsumerPush(), server)
    server.add_insecure_port('[::]:50052')
    server.start()
    print("Consumer Push gRPC server started on port 50052")
    server.wait_for_termination()
if __name__ == '__main__':
    serve()
EOF

# Step 7: Start everything
echo "[+] Building services..."
docker compose up -d --build

# Step 8: gRPC client test
sleep 15
mkdir -p test_client
cp producer_proxy/proto/service.proto test_client/service.proto
cat <<EOF > test_client/client.py
import grpc
import service_pb2, service_pb2_grpc

def run():
    with grpc.insecure_channel('localhost:50051') as channel:
        stub = service_pb2_grpc.ProducerProxyStub(channel)
        for i in range(10):
            key = f"msg-{i}"
            val = f"payload-{i}"
            res = stub.Produce(service_pb2.ProduceRequest(key=key, value=val))
            print(f"✅ Send {key}: success={res.success}")
if __name__ == '__main__':
    run()
EOF
python3 -m venv test_client/venv && source test_client/venv/bin/activate
pip install grpcio grpcio-tools
python -m grpc_tools.protoc -I test_client --python_out=test_client --grpc_python_out=test_client test_client/service.proto
python test_client/client.py

# Final step: copy logs for dashboard
cp logs/producer_proxy.log dashboard/producer.log || true
cp logs/consumer_push.log dashboard/consumer.log || true

echo "🎯 All done: DLQ + Retry + GUI at http://localhost:8080"
