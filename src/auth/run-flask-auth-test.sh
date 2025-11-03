curl -X POST -H "Content-Type: application/json" -u "dksahuji@gmail.com:Admin123" http://127.0.0.1:5000/login > token.txt
curl -X POST -H "Authorization: Bearer $(cat token.txt)" http://127.0.0.1:5000/validate
rm token.txt