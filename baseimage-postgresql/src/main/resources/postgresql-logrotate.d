/var/log/postgresql/postgresql-*-main.log {
   su postgres postgres
   copytruncate
   daily
   rotate 28
   dateext
   compress
   missingok
   create 640 postgres postgres
}