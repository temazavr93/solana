catchup_info() {
  while true; do
    sudo -i -u root solana catchup --our-localhost
    status=$?
    if [ $status -eq 0 ];then
      exit 0
    fi
    echo "waiting next 30 seconds for rpc"
    sleep 30
  done
}

systemctl stop solana
cd /root/solana
rm -fr solana-snapshot-finder
rm -fr /root/solana/ledger/*
sudo apt-get update
sudo apt-get install python3-venv git -y
git clone https://github.com/c29r3/solana-snapshot-finder.git
cd solana-snapshot-finder
python3 -m venv venv
source ./venv/bin/activate
pip3 install -r requirements.txt
python3 snapshot-finder.py --snapshot_path /root/solana/ledger --min_download_speed 90 --max_latency 150
systemctl start solana
catchup_info


