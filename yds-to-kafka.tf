# Infrastructure for the Yandex Cloud YDB, Managed Service for Apache Kafka® and Data Transfer.
#
# RU: https://cloud.yandex.ru/ru/docs/data-transfer/tutorials/yds-to-kafka
# EN: https://cloud.yandex.com/en/docs/data-transfer/tutorials/yds-to-kafka
#
# Set source database and target cluster settings.

locals {
  # YDB settings:
  ydb_name           = "" # Set a YDB database name.
  source_endpoint_id = "" # Set the source endpoint id.

  # Managed Service for Apache Kafka® cluster settings:
  mkf_version        = "" # Set Managed Service for Apache Kafka® cluster version.
  mkf_user_name      = "" # Set a username in the Managed Service for Apache Kafka® cluster.
  mkf_user_password  = "" # Set a password for the user in the Managed Service for Apache Kafka® cluster.
  target_endpoint_id = "" # Set the target endpoint id.

  # Transfer settings:
  transfer_enable = 0 # Set to 1 to enable Transfer.
}

resource "yandex_vpc_network" "network" {
  name        = "network"
  description = "Network for the Managed Service for Apache Kafka® cluster and Yandex Cloud YDB"
}

# Subnet in ru-central1-a availability zone
resource "yandex_vpc_subnet" "subnet-a" {
  name           = "subnet-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.network.id
  v4_cidr_blocks = ["10.1.0.0/16"]
}

# Security group for the Managed Service for Apache Kafka® cluster
resource "yandex_vpc_default_security_group" "security-group" {
  network_id = yandex_vpc_network.network.id

  ingress {
    protocol       = "TCP"
    description    = "Allow connections to the Managed Service for Apache Kafka® cluster from the Internet"
    port           = 9091
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    description    = "Allow outgoing connections to any required resource"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# Managed Service for Apache Kafka® cluster
resource "yandex_mdb_kafka_cluster" "kafka-cluster" {
  name               = "kafka-cluster"
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.network.id
  security_group_ids = [yandex_vpc_default_security_group.security-group.id]

  config {
    assign_public_ip = true
    brokers_count    = 1
    version          = local.kf_version
    zones            = ["ru-central1-a"]
    kafka {
      resources {
        resource_preset_id = "s2.micro"
        disk_type_id       = "network-hdd"
        disk_size          = 10 # GB
      }
    }
  }
}

resource "yandex_mdb_kafka_user" "kafka-user" {
  cluster_id = yandex_mdb_kafka_cluster.kafka-cluster.id
  name       = local.mkf_user_name
  password   = local.mkf_user_password
  permission {
    topic_name = "sensors"
    role       = "ACCESS_ROLE_CONSUMER"
  }
  permission {
    topic_name = "sensors"
    role       = "ACCESS_ROLE_PRODUCER"
  }
}

resource "yandex_mdb_kafka_topic" "sensors" {
  cluster_id         = yandex_mdb_kafka_cluster.kafka-cluster.id
  name               = "sensors"
  partitions         = 4
  replication_factor = 1
}

resource "yandex_ydb_database_serverless" "ydb" {
  name        = local.ydb_name
  location_id = "ru-central1"
}

resource "yandex_datatransfer_transfer" "yds-mkf-transfer" {
  count       = local.transfer_enable
  description = "Transfer from the YDB (DS) to the Apache Kafka® cluster"
  name        = "transfer-from-yds-to-mkf"
  source_id   = local.source_endpoint_id
  target_id   = local.target_endpoint_id
  type        = "INCREMENT_ONLY" # Replication data from the source Data Stream.
}

