provider "aws" {
  region = "us-east-2"
}

resource "aws_s3_bucket" "puc_bucket_flask" {
  bucket = "puc-pellizzi09-bucket"

  tags = {
    Name        = "puc Bucket"
    Environment = "eixo4"
  }

  provisioner "local-exec" {
    command = "${path.module}/upload_to_s3.sh"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "aws s3 rm s3://puc-pellizzi09-bucket --recursive"
  }
}

resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "puc-app-log-group"
  retention_in_days = 14
}

resource "aws_iam_role" "ec2_s3_access_role" {
  name = "ec2_s3_access_role"

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

resource "aws_iam_role_policy" "s3_access_policy" {
  name = "s3_access_policy"
  role = aws_iam_role.ec2_s3_access_role.id

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

resource "aws_iam_instance_profile" "ec2_s3_profile" {
  name = "ec2_s3_profile"
  role = aws_iam_role.ec2_s3_access_role.name
}

resource "aws_security_group" "puc_api_sg" {
  name        = "puc_api_sg"
  description = "Security Group for Flask App in EC2"

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

  egress {
    description = "All traffic"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "puc_api" {
  ami                    = "ami-0a0d9cf81c479446a"
  instance_type          = "t2.micro"
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
