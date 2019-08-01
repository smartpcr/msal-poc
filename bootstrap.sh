echo "installing kubectl..."
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x kubectl
sudo mv ./kubectl /usr/local/bin/kubectl

echo "installing helm..."
curl -LO https://get.helm.sh/helm-v2.14.3-linux-amd64.tar.gz 
tar -zxvf helm-v2.14.3-linux-amd64.tar.gz
chmod +x ./linux-amd64/helm
sudo mv ./linux-amd64/helm /usr/local/bin/helm
rm helm-v2.14.3-linux-amd64.tar.gz
rm -rf linux-amd64

echo "installing fabrikate..."
curl -LO 'https://github-production-release-asset-2e65be.s3.amazonaws.com/161809588/172dc100-a744-11e9-9bf6-101184bd1f9e?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIWNJYAX4CSVEH53A%2F20190731%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20190731T193407Z&X-Amz-Expires=300&X-Amz-Signature=ba2bc425cc51c74ada32b604b24b323a94fd033bdd8b8545ffe3883b9a78e7ab&X-Amz-SignedHeaders=host&actor_id=19724544&response-content-disposition=attachment%3B%20filename%3Dfab-v0.15.1-linux-amd64.zip&response-content-type=application%2Foctet-stream'
tar -zxvf fab-v0.15.1-linux-amd64.zip 
rm fab-v0.15.1-linux-amd64.zip
chmod +x fab
sudo mv ./fab /usr/local/bin/fab
