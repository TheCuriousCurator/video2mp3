sudo apt-get install libmysqlclient-dev

sudo mysql -u root < init.sql 

sudo mysql -u root 
    show databases;
    use auth;
    show tables;
    describe user;
    select * from user;