CREATE ROLE arvados_sso WITH SUPERUSER LOGIN PASSWORD 'xxxxxxxx';
create database arvados_sso_production with template = template0 encoding = 'UTF8';
