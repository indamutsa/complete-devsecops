# Define IAM policy for EKS cluster role assumption
data "aws_iam_policy_document" "eks_assume_role_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# Create IAM role for EKS cluster
resource "aws_iam_role" "eks_cluster" {
  name               = "eks-cluster-cloud"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role_policy.json
}

# Attach AmazonEKSClusterPolicy to the EKS cluster IAM role
resource "aws_iam_role_policy_attachment" "eks_cluster_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# Fetch the default VPC (ensure it exists and is intended for use)
data "aws_vpc" "default" {
  default = true
}

# Define IAM policy for EKS node group role assumption
resource "aws_iam_role" "eks_node_group" {
  name = "eks-node-group-cloud"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Attach policies required by EKS worker nodes to the node group IAM role
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "ecr_read_only_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group.name
}

# Create a subnet within the VPC for EKS cluster and node group
resource "aws_subnet" "eks_subnet" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = "172.31.0.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-1"
    Tier = "public"
  }
}

resource "aws_subnet" "eks_subnet2" {
  vpc_id                  = data.aws_vpc.default.id
  cidr_block              = "172.31.1.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-2"
    Tier = "public"
  }
}

# Create the EKS cluster
resource "aws_eks_cluster" "example" {
  name     = "EKS_CLOUD"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = [aws_subnet.eks_subnet.id, aws_subnet.eks_subnet2.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy_attachment,
  ]
}

# Create an EKS node group within the cluster
resource "aws_eks_node_group" "example" {
  cluster_name    = aws_eks_cluster.example.name
  node_group_name = "Node-cloud"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = [aws_subnet.eks_subnet.id, aws_subnet.eks_subnet2.id]

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }

  instance_types = ["t2.medium"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy_attachment,
    aws_iam_role_policy_attachment.eks_cni_policy_attachment,
    aws_iam_role_policy_attachment.ecr_read_only_policy_attachment,
  ]
}

# Output the ID of the created subnet
output "public_subnet_ids" {
  value = [aws_subnet.eks_subnet.id, aws_subnet.eks_subnet2.id]
}
