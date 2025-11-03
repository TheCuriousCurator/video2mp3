./undeploy.sh
./deploy.sh
./start-services.sh
rm token.txt
curl -X POST -u 'dksahuji@gmail.com:Admin123' http://video2mp3.com/login > token.txt
curl -X POST -F 'file=@./agentic_ai-using-external-feedback.mp4' -H "Authorization: Bearer $(cat token.txt)" http://video2mp3.com/upload
