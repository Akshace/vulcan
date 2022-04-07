# Download the necessary files
git clone https://github.com/ratchahan-anbarasan/jetstream_kubespray.git &&
cd jetstream_kubespray &&
git checkout -b branch_v2.15.0 origin/branch_v2.15.0 &&
cd .. &&
git clone https://github.com/airavata-courses/vulcan.git &&
cd vulcan &&
git checkout develop-ansible-K8S &&
cd .. &&
sudo apt-get update &&

# Install terraform 0.14.4
sudo apt-get install zip unzip &&
wget https://releases.hashicorp.com/terraform/0.14.4/terraform_0.14.4_linux_amd64.zip &&
unzip terraform_0.14.4_linux_amd64.zip &&
sudo chmod +x terraform &&
sudo cp terraform /usr/local/bin/ &&
sudo mv terraform /usr/bin/ &&
rm -rf terraform_0.14.4_linux_amd64.zip &&

# Change the directory
cd jetstream_kubespray &&

# Export cluser name
export CLUSTER=vulcan &&
cp -r inventory/kubejetstream inventory/$CLUSTER &&
cd inventory/$CLUSTER &&

# Update the IP address you have provided
sed -i '/k8s_master_fips/c\k8s_master_fips =["'$IP'"]'  cluster.tfvars &&
bash terraform_init.sh &&
bash terraform_apply.sh &&

# Sleeping for 30 seconds just for instances to start
sleep 30 &&
cd ../../ &&

# installing Ansible
pip3 install -r requirements.txt &&
eval $(ssh-agent -s) &&
ssh-add ~/.ssh/id_rsa &&

# This will avoid the yes/no prompt when doing SSH connection to the machines
echo 'StrictHostKeyChecking no' &>> /etc/ssh/ssh_config &&

# Run the ansible playbooks to install kubernetes
cd ../vulcan/deployments &&
cp ../../jetstream_kubespray/inventory/$CLUSTER/hosts hosts &&
ansible-playbook -i hosts users.yml &&
sleep 20 &&
ansible-playbook -i hosts install-k8s.yml &&
sleep 30 &&
ansible-playbook -i hosts master.yml &&
sleep 30 &&
ansible-playbook -i hosts workers.yml &&

scp ../kubernetes ubuntu@IP:/home/ubuntu/deploy/kubernetes
scp docker-compose.yml ubuntu@IP:/home/ubuntu/deploy/
scp deploy.sh ubuntu@IP:/home/ubuntu/deploy/

ssh ubuntu@$IP