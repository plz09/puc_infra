provider "aws" {
  region = "us-east-2"
}

resource "aws_s3_bucket" "puc_bucket_flask" {
  bucket = "puc-pellizzi09-bucket"

  tags = {
    Name        = "puc Bucket"
    Environment = "eixo4"
  }
  # Executa um script local (upload_to_s3.sh) logo após a criação do bucket
  provisioner "local-exec" {
    command = "${path.module}/upload_to_s3.sh"
  }

  # Quando o bucket for destruído, apaga todos os arquivos dentro dele
  provisioner "local-exec" {
    when    = destroy
    command = "aws s3 rm s3://puc-pellizzi09-bucket --recursive"
  }
}

# Cria um grupo de logs no CloudWatch com retenção de 14 dias. Os logs da aplicação serão enviados para cá
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "puc-app-log-group"
  retention_in_days = 14
}

# Define uma role para EC2, permitindo que ela assuma permissões
resource "aws_iam_role" "ec2_s3_access_role" {
  name = "ec2_s3_access_role"

  # Permite que instâncias EC2 assumam essa role
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Define permissões da EC2 para interagir com o bucket S3
resource "aws_iam_role_policy" "s3_access_policy" {
  name = "s3_access_policy"
  role = aws_iam_role.ec2_s3_access_role.id

  # Permissões: listar o bucket, ler e enviar arquivos
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ],
        Resource = [
          "arn:aws:s3:::puc-pellizzi09-bucket",
          "arn:aws:s3:::puc-pellizzi09-bucket/*"
        ]
      }
    ]
  })
}

# Permite que a EC2 colete e envie métricas/logs para o CloudWatch
resource "aws_iam_role_policy" "cloudwatch_agent_policy" {
  name = "cloudwatch_agent_policy"
  role = aws_iam_role.ec2_s3_access_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "cloudwatch:PutMetricData"
        ],
        Resource = "*"
      }
    ]
  })
}

# Cria um perfil de instância que associa a role criada à EC2
resource "aws_iam_instance_profile" "ec2_s3_profile" {
  name = "ec2_s3_profile"
  role = aws_iam_role.ec2_s3_access_role.name
}

# Define um grupo de segurança para controlar o tráfego de entrada e saída da instância
resource "aws_security_group" "puc_api_sg" {
  name        = "puc_api_sg"
  description = "Security Group for Flask App in EC2"

  # Libera acesso nas portas 80 (web), 5000 (Flask app) e 22 (SSH)
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "App Port"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Libera todo o tráfego de saída da instância.
  egress {
    description = "All traffic"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Cria uma instância EC2 pequena, com AMI Amazon Linux 2
resource "aws_instance" "puc_api" {
  ami                    = "ami-0a0d9cf81c479446a"
  instance_type          = "t2.micro"

  # Aplica o perfil IAM e o grupo de segurança criado
  iam_instance_profile   = aws_iam_instance_profile.ec2_s3_profile.name
  vpc_security_group_ids = [aws_security_group.puc_api_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y python3 python3-pip awscli amazon-cloudwatch-agent

              pip3 install flask boto3 gunicorn pandas "urllib3<2.0" "prefect<2.0"

              mkdir -p /puc_app
              aws s3 sync s3://puc-pellizzi09-bucket /puc_app
              chown -R ec2-user:ec2-user /puc_app
              cd /puc_app
              nohup gunicorn -w 4 -b 0.0.0.0:5000 app:app > /tmp/gunicorn.log 2>&1 &

              cat <<EOT > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
              {
                "agent": {
                  "metrics_collection_interval": 60,
                  "run_as_user": "root"
                },
                "logs": {
                  "logs_collected": {
                    "files": {
                      "collect_list": [
                        {
                          "file_path": "/tmp/app.log",
                          "log_group_name": "puc-app-log-group",
                          "log_stream_name": "app.py",
                          "timestamp_format": "%Y-%m-%d %H:%M:%S"
                        }
                      ]
                    }
                  }
                },
                "metrics": {
                  "metrics_collected": {
                    "cpu": {
                      "measurement": ["usage_idle", "usage_user", "usage_system"],
                      "totalcpu": true
                    },
                    "mem": {
                      "measurement": ["mem_used_percent"]
                    },
                    "disk": {
                      "measurement": ["used_percent"],
                      "resources": ["*"]
                    }
                  }
                }
              }
              EOT

              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
                -a fetch-config \
                -m ec2 \
                -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
                -s
              EOF

  tags = {
    Name = "pucFlaskApp"
  }
}
