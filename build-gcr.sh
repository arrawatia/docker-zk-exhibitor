docker build -t quantezza/zk-exhibitor .
docker tag -f quantezza/zk-exhibitor gcr.io/quantiply-edge-cloud/zk-exhibitor-3.4.6:v1
echo y | gcloud docker push gcr.io/quantiply-edge-cloud/zk-exhibitor-3.4.6:v1

gsutil -m acl ch -R -g AllUsers:R gs://artifacts.quantiply-edge-cloud.appspot.com
