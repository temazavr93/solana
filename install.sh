#!/bin/bash
#set -x -e
echo "###################### WARNING!!! ###################################"
echo "###   This script will perform the following operations:          ###"
echo "###   * download and install validator binaries                   ###"
echo "###   * system tuning                                             ###"
echo "###   * create vote account (option)                              ###"
echo "###   * create service files                                      ###"
echo "###   * install monitoring (option)                               ###"
echo "###   * configure firewall                                        ###"
echo "###   * create ramdisk (option)                                   ###"
echo "###                                                               ###"
echo "###   *** Script provided by SOLSTAKER.RPO                        ###"
echo "#####################################################################"
echo
echo "### Which version should I install?? ###"

  select cluster in "mainnet-beta" "testnet"; do
      case $cluster in
          mainnet-beta )
            url="https://api.mainnet-beta.solana.com"
            solanaversion="$(wget -q -4 -O- https://solstaker.pro/scripts/solana-mainnet/actual_version)"
			      clusternetwork="mainnet"
            break;;
          testnet )
            url="https://api.testnet.solana.com"
            solanaversion="$(wget -q -4 -O- https://solstaker.pro/scripts/solana-testnet/actual_version)"
			      clusternetwork="testnet"
            break;;
      esac
  done
  
mkdir -p /root/solana
apt update -y && apt upgrade -y && apt install curl gnupg git ufw wget -y

install_solana() {
echo "######################################"
echo "### Installing Solana $solanaversion $cluster" 
echo "######################################"

sh -c "$(curl -sSfL https://release.solana.com/v$solanaversion/install)" && \
export PATH="/root/.local/share/solana/install/active_release/bin:$PATH"
cd /root/solana
}

see_version_and_setting() {
solana --version && \
solana config set --url $url --keypair ~/solana/validator-keypair.json
}

system_tuning() {
echo "######################################"
echo "### 	   Start system tuning		 "
echo "######################################"

sudo bash -c "cat >/etc/sysctl.d/21-solana-validator.conf <<EOF
# Increase UDP buffer sizes
net.core.rmem_default = 134217728
net.core.rmem_max = 134217728
net.core.wmem_default = 134217728
net.core.wmem_max = 134217728

# Increase memory mapped files limit
vm.max_map_count = 1000000

# Increase number of allowed open file descriptors
fs.nr_open = 1000000
EOF"

sudo bash -c "cat >/etc/security/limits.d/90-solana-nofiles.conf <<EOF
# Increase process file descriptor count limit
* - nofile 1000000
EOF"


sudo bash -c "cat >/etc/sysctl.d/20-solana-udp-buffers.conf <<EOF
# Increase UDP buffer size
net.core.rmem_default = 134217728
net.core.rmem_max = 134217728
net.core.wmem_default = 134217728
net.core.wmem_max = 134217728
EOF"

sudo bash -c "cat >/etc/sysctl.d/20-solana-mmaps.conf <<EOF
# Increase memory mapped files limit
vm.max_map_count = 1000000
EOF"

if [[ $clusternetwork = testnet ]];then 
echo "This is testnet. No edit fstrim.timer"
elif [ $clusternetwork = mainnet ];then 
echo "Edit /lib/systemd/system/fstrim.timer"
cat > /etc/telegraf/telegraf.conf <<EOF
[Unit]
Description=Discard unused blocks once a week
Documentation=man:fstrim
ConditionVirtualization=!container

[Timer]
OnCalendar=daily
AccuracySec=1h
Persistent=true

[Install]
WantedBy=timers.target

EOF
fi

cd /root/solana
wget https://solstaker.pro/scripts/systuner.service
}

create_vote_account() {
echo "######################################"
echo "### 	   Create vote account?		 "
echo "######################################"
select new_vote in "Yes, don't use password for keypair (--no-bip39-passphrase)" "Yes, use password for keypair (bip39-passphrase)" "No"; do
    case $new_vote in
        "Yes, don't use password for keypair (--no-bip39-passphrase)")
			if [[ $clusternetwork = mainnet ]];then
			solana-keygen new --no-bip39-passphrase -o ~/solana/vote-account-keypair.json
			solana-keygen new --no-bip39-passphrase -o ~/solana/aw.json
			solana create-vote-account ~/solana/vote-account-keypair.json ~/solana/validator-keypair.json ~/solana/aw.json --commission 10
			else
			solana-keygen new --no-bip39-passphrase -o ~/solana/vote-account-keypair.json
			solana-keygen new --no-bip39-passphrase -o ~/solana/aw.json
			solana airdrop 1 $(solana address)
			solana create-vote-account ~/solana/vote-account-keypair.json ~/solana/validator-keypair.json ~/solana/aw.json
			fi
			break
            ;;
		"Yes, use password for keypair (bip39-passphrase)")
		    if [[ $clusternetwork = mainnet ]];then
			solana-keygen new -o ~/solana/vote-account-keypair.json
			solana-keygen new -o ~/solana/aw.json
			solana create-vote-account ~/solana/vote-account-keypair.json ~/solana/validator-keypair.json ~/solana/aw.json --commission 10
			else
			solana-keygen new -o ~/solana/vote-account-keypair.json
			solana-keygen new -o ~/solana/aw.json
			solana airdrop 1 $(solana address)
			solana create-vote-account ~/solana/vote-account-keypair.json ~/solana/validator-keypair.json ~/solana/aw.json
			fi
			break
            ;;
        "No")
            break
            ;;
        *) echo "invalid option $REPLY";;
    esac
done
}

create_solana.service() {
echo "######################################"
echo "### 	   Create service files		 "
echo "######################################"
if [[ $clusternetwork = testnet ]];then 
cd /root/solana
wget https://solstaker.pro/scripts/solana-testnet/solana.service
elif [ $clusternetwork = mainnet ];then 
cd /root/solana
wget https://solstaker.pro/scripts/solana-mainnet/solana.service
fi
echo "### 	   Complete		 "
}

create_solana.logrotate() {
cat > /root/solana/solana.logrotate <<EOF
/root/solana/solana.log {
  rotate 7
  daily
  missingok
  postrotate
    systemctl kill -s USR1 solana.service
  endscript
}
EOF
}

create_symbolic_link() {
echo "######################################"
echo "### 	   Create symbolic link 		 "
echo "######################################"
sudo ln -s /root/solana/solana.service /etc/systemd/system
sudo ln -s /root/solana/systuner.service /etc/systemd/system
sudo ln -s /root/solana/solana.logrotate /etc/logrotate.d/
systemctl daemon-reload
}

install_monitoring() {
echo "######################################"
echo "### 	   Install monitoring		 "
echo "######################################"
cat <<EOF | tee /etc/apt/sources.list.d/influxdata.list
deb https://repos.influxdata.com/ubuntu bionic stable
EOF
curl -sL https://repos.influxdata.com/influxdb.key | apt-key add -
apt-get update
apt-get -y install telegraf jq bc
adduser telegraf sudo
adduser telegraf adm
echo "telegraf ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
cp /etc/telegraf/telegraf.conf /etc/telegraf/telegraf.conf.orig
rm -rf /etc/telegraf/telegraf.conf
cd /root/solana && git clone https://github.com/solstaker/solanamonitoring/
chmod +x /root/solana/solanamonitoring/monitor.sh
echo "######################################"
echo "### Please type your validator name "
echo "######################################"
read -p "Validator name:" VALIDATOR_NAME
touch /etc/telegraf/telegraf.conf
cat > /etc/telegraf/telegraf.conf <<EOF
# Global Agent Configuration
[agent]
  hostname = "$VALIDATOR_NAME" # set this to a name you want to identify your node in the grafana dashboard
  flush_interval = "15s"
  interval = "15s"
# Input Plugins
[[inputs.cpu]]
    percpu = true
    totalcpu = true
    collect_cpu_time = false
    report_active = false
[[inputs.disk]]
    ignore_fs = ["devtmpfs", "devfs"]
[[inputs.mem]]
[[inputs.net]]
[[inputs.system]]
[[inputs.swap]]
[[inputs.netstat]]
[[inputs.processes]]
[[inputs.kernel]]
[[inputs.diskio]]
# Output Plugin InfluxDB
[[outputs.influxdb]]
  database = "metricsdb"
  urls = [ "http://metrics.stakeconomy.com:8086" ] # keep this to send all your metrics to the community dashboard otherwise use http://yourownmonitoringnode:8086
  username = "metrics" # keep both values if you use the community dashboard
  password = "password"
[[inputs.exec]]
  commands = ["sudo su -c /root/solana/solanamonitoring/monitor.sh -s /bin/bash root"] # change home and username to the useraccount your validator runs at
  interval = "3m"
  timeout = "1m"
  data_format = "influx"
  data_type = "integer"
EOF
}

ufw_configure() {
echo "######################################"
echo "### 	   Configure ufw firewall		 "
echo "### 	   Enable ufw (y|n)? "
echo "######################################"
sudo ufw allow 22/tcp
sudo ufw allow 2222/tcp
sudo ufw allow 8000:8020/udp
sudo ufw allow 10050
sudo ufw deny out from any to 10.0.0.0/8
sudo ufw deny out from any to 172.16.0.0/12
sudo ufw deny out from any to 192.168.0.0/16
sudo ufw deny out from any to 100.64.0.0/10
sudo ufw deny out from any to 198.18.0.0/15
sudo ufw deny out from any to 169.254.0.0/16
sudo ufw enable
}

ramdisk_setup() {
read -p "Enter new RAM drive size, GB (default: 200):" RAMDISK
read -p "Enter new server swap size GB (ramdisk minus free RAM; default: 168) :" SWAP

solanadir=/root/solana
servicefile=$solanadir/solana.service

 if [ -d /mnt/ramdisk ];then
echo "ramdisk already exists"
df -h | grep ramdisk
else
swapoff -a  # off current swap
echo "create new swapfile; size "$SWAP"G "
dd if=/dev/zero of=/swapfile bs=1G count=$SWAP 	# create swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "Adding swap & RAMDISK to /etc/fstab"
sed -i '/swap/s/^/#/' /etc/fstab # off old swap
echo "/swapfile none swap sw 0 0
tmpfs /mnt/ramdisk tmpfs nodev,nosuid,noexec,nodiratime,size="$RAMDISK"G 0 0" >> /etc/fstab
echo "Create & mount RAMDISK"
mkdir -p /mnt/ramdisk
mount /mnt/ramdisk
fi
}
 

 
 
 
install_solana
see_version_and_setting
create_vote_account
system_tuning
create_solana.service
create_solana.logrotate
create_symbolic_link

echo "### Install monitoring?? ###"
  select monitoring in "Yes" "No"; do
      case $monitoring in
          Yes )
            install_monitoring        			
            break;;
          No )
            break;;
      esac
  done
  
ufw_configure

echo "### Create RAMDISK??  ###"
  select createramdisk in "Yes" "No"; do
      case $createramdisk in
          Yes )
            ramdisk_setup        			
            break;;
          No )
            break;;
      esac
  done


echo "### Enable telegraf and solana service on startup system ###"

sudo systemctl enable --now telegraf
sudo systemctl enable /root/solana/solana.service
sudo systemctl enable /root/solana/systuner.service

echo "### Install is complete. 							   "
echo "### Server name: $VALIDATOR_NAME			   "
echo "### Cluster: $clusternetwork					   "
echo "### You identity pubkey: $(solana address)"
echo "### You vote pubkey: $(solana-keygen pubkey /root/solana/vote-account-keypair.json)"
echo "### You balance: $(solana balance)"
echo "### You IP: $(wget -q -4 -O- http://icanhazip.com)"
echo "### Please reboot your server."
exit 0
