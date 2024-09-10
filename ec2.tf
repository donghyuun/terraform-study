  provider "aws" {
    region = "ap-northeast-2"
  }

  # ---------- TLS 개인 키 생성 --------
  /*
  이 리소스는 개인 키를 생성하며, 이와 함께 공개 키도 생성
  공개 키는 tls_private_key.katecam_make_key.public_key_openssh로 접근 가능
  개인 키는 tls_private_key.katecam_make_key.private_key_pem로 접근 가능
  */
  resource "tls_private_key" "katecam_make_key" { # 공개 및 개인 키 생성
    algorithm = "RSA"
    rsa_bits  = 4096
  }

  # AWS 키 페어 생성
  /*
  AWS에서는 공개 키를 저장하여 EC2 인스턴스에 배포
  인스턴스는 이 공개 키를 사용하여 SSH 접근을 허용
  EC2 인스턴스는 개인 키를 저장하지 않기 때문에 로컬에서 가지고 있어야 함
  */
  resource "aws_key_pair" "katecam_make_keypair" { # 키 페어 리소스 이름
    key_name   = "katecam_key" # 키 이름
    public_key = tls_private_key.katecam_make_key.public_key_openssh # katecam_make_key 리소스에서 생성된 공개 키를 사용
  }

  # 로컬 파일에 개인 키 저장
  /*
  개인 키를 저장해야 SSH 접근 시 사용할 수 있음
  */
  resource "local_file" "katecam_downloads_key" { # 개인 키 리소스 이름
    filename = "katecam_key.pem" # 파일 이름 설정
    content  = tls_private_key.katecam_make_key.private_key_pem # 리소스에서 생성된 개인 키를 저장
  }

  # --------- 보안 그룹 설정 --------- 
  /*
  AWS 에서 인스턴스와 같은 리소스의 네트워크 트래픽을 제어하는 방화벽 역할
  인바운드, 아웃바운드 트래픽 규칙을 정의
  */
  resource "aws_security_group" "katecam_security" { # 보안 그룹 리소스 이름
    name_prefix = "katecam_security_group" # 보안 그룹 리스트에 등록될 이름
    vpc_id      = aws_vpc.katecam_vpc.id # 보안 그룹이 연결될 VPC, EC2 에 적용하기 전 먼저 EC2 가 사용할 VPC 와 연결해줘야 함
  }

  # 인바운드 - SSH
  resource "aws_security_group_rule" "ingress_ssh" { # 보안 규칙 리소스 이름
    type             = "ingress" # 규칙 타입 
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    security_group_id = aws_security_group.katecam_security.id 
  }

  # 인바운드 - HTTPS
  resource "aws_security_group_rule" "ingress_https" {
    type             = "ingress"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    security_group_id = aws_security_group.katecam_security.id
  }

  # 인바운드 - HTTP
  resource "aws_security_group_rule" "ingress_http" {
    type             = "ingress"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    security_group_id = aws_security_group.katecam_security.id
  }

  # 인바운드 - 스프링부트
  resource "aws_security_group_rule" "ingress_spring_boot" {
    type             = "ingress"
    from_port        = 8080
    to_port          = 8080
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    security_group_id = aws_security_group.katecam_security.id
  }

  # 아웃바운드 - 모든 트래픽 허용
  resource "aws_security_group_rule" "egress_all" {
    type             = "egress"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    security_group_id = aws_security_group.katecam_security.id
  }

  # VPC 정의
  /*
  AWS VPC 리소스를 정의
  */
  resource "aws_vpc" "katecam_vpc" {
    cidr_block = "10.0.0.0/16"
    
    tags = {
      Name = "Katecam-vpc"
    }
  }

  # 서브넷 정의 (가용 영역 지정)
  resource "aws_subnet" "katecam_subnet" {
    cidr_block = "10.0.1.0/24" # VPC 에서의 서브넷이 사용할 IP 범위
    vpc_id     = aws_vpc.katecam_vpc.id # 서브넷이 속할 vpc 
    availability_zone = "ap-northeast-2a" # 또는 다른 지원되는 가용 영역
    
    tags = {
      Name = "katecam-subnet"
    }
  }

  # EC2 인스턴스 정의
  resource "aws_instance" "katecam_instance" {
    ami                      = "ami-05d2438ca66594916" # 운영체제 이미지 - ubuntu
    instance_type            = "t2.micro" # EC2 인스턴스 타입
    key_name                 = aws_key_pair.katecam_make_keypair.key_name # EC2 SSH 접근 시 사용할 공개 키 저장
    vpc_security_group_ids   = [aws_security_group.katecam_security.id] # 보안 그룹 설정
    subnet_id                = aws_subnet.katecam_subnet.id # 서브넷 ID 추가
    associate_public_ip_address = true # 퍼블릭 IP 주소 할당 여부

    root_block_device {
        volume_size = 30 # 볼륨 크기 설정 (GiB)
        volume_type = "gp3" # 일반적인 범용 SSD (gp2) 타입
    }

    # 스왑 메모리 설정을 위한 user_data 스크립트
    user_data = <<EOF
      #!/bin/bash
      # Create a swap file of 20GB
      sudo fallocate -l 20G /swapfile
      sudo chmod 600 /swapfile
      sudo mkswap /swapfile
      sudo swapon /swapfile

      # Make swap file permanent by adding it to /etc/fstab
      echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab
    EOF

    tags = {
      Name = "katecam-instance"
    }
  }

  # --------- 인터넷 게이트웨이, 라우팅 테이블 생성 ---------
  # 인터넷 게이트웨이 
  resource "aws_internet_gateway" "katecam_igw" {
      vpc_id = aws_vpc.katecam_vpc.id

      tags = {
          Name = "katecam-igw"
      }
  }
  # 라우팅 테이블
  resource "aws_route_table" "katecam_rt" {
      vpc_id = aws_vpc.katecam_vpc.id

      route {
          cidr_block = "0.0.0.0/0" # 모든 IP 주소에 대해
          gateway_id = aws_internet_gateway.katecam_igw.id # 인터넷 게이트웨이로 라우팅
      }

      tags = {
          Name = "katecam-rt"
      }
  }
  # 서브넷에 라우팅 테이블 적용
  resource "aws_route_table_association" "katecam_rta" {
      subnet_id = aws_subnet.katecam_subnet.id
      route_table_id = aws_route_table.katecam_rt.id
  }

  # 같은 Subnet 통신 간 내부 통신 보안 그룹 열기
  # 보안 그룹의 인바운드 규칙을 적용, 아웃바운드는 위에서 모두 열어놨음
  resource "aws_security_group_rule" "katecam_security_ingress_internal"{
    type = "ingress"
    from_port = 0 # 모든 포트에 대해 들어오는 트래픽 허용
    to_port = 0 # 모든 포트에 대해 나가는 트래픽 허용
    protocol = "-1" # 모든 프로토콜에 대해 트래픽 허용
    source_security_group_id = aws_security_group.katecam_security.id # 인바운드 트래픽 출처가 될 보안그룹 지정
    security_group_id = aws_security_group.katecam_security.id # 이 규칙이 적용될 보안 그룹
    # -> 즉 katecam_security 보안 그룹에 속한 인스턴스들 간에 모든 포트와 프로토콜에 대해 자유롭게 통신할 수 있도록 허용
  }
