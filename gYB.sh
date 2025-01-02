#!/bin/sh
source ~/.bash_profile

function tyb
{
echo '==============='
ssh 31.0.31.51 -p 10022 df -h | grep /opt | grep -v IBM_Tivoli
ssh 31.0.31.52 -p 10022 df -h | grep /opt | grep -v IBM_Tivoli
ssh 31.0.31.53 -p 10022 df -h | grep /opt | grep -v IBM_Tivoli
ssh 31.0.31.54 -p 10022 df -h | grep /opt | grep -v IBM_Tivoli
ssh 31.0.31.55 -p 10022 df -h | grep /opt | grep -v IBM_Tivoli
ssh 31.0.31.56 -p 10022 df -h | grep /opt | grep -v IBM_Tivoli
ssh 31.0.31.57 -p 10022 df -h | grep /opt | grep -v IBM_Tivoli
ssh 31.0.31.58 -p 10022 df -h | grep /opt | grep -v IBM_Tivoli
echo '==============='
echo ''
echo '===== 51 ======'
ssh 31.0.31.51 -p 10022 free -g
echo '----- 52 ------'
ssh 31.0.31.52 -p 10022 free -g
echo '----- 53 ------'
ssh 31.0.31.53 -p 10022 free -g
echo '----- 54 ------'
ssh 31.0.31.54 -p 10022 free -g
echo '----- 55 ------'
ssh 31.0.31.55 -p 10022 free -g
echo '----- 56 ------'
ssh 31.0.31.56 -p 10022 free -g
echo '----- 57 ------'
ssh 31.0.31.57 -p 10022 free -g
echo '----- 58 ------'
ssh 31.0.31.58 -p 10022 free -g
echo '==============='
echo ''
echo '===== 51 ======'
ssh 31.0.31.51 -p 10022 sar -n EDEV 1 1|grep -iE "IFACE|bond0"
echo '----- 52 ------'
ssh 31.0.31.52 -p 10022 sar -n EDEV 1 1|grep -iE "IFACE|bond0"
echo '----- 53 ------'
ssh 31.0.31.53 -p 10022 sar -n EDEV 1 1|grep -iE "IFACE|bond0"
echo '----- 54 ------'
ssh 31.0.31.54 -p 10022 sar -n EDEV 1 1|grep -iE "IFACE|bond0"
echo '----- 55 ------'
ssh 31.0.31.55 -p 10022 sar -n EDEV 1 1|grep -iE "IFACE|bond0"
echo '----- 56 ------'
ssh 31.0.31.56 -p 10022 sar -n EDEV 1 1|grep -iE "IFACE|bond0"
echo '----- 57 ------'
ssh 31.0.31.57 -p 10022 sar -n EDEV 1 1|grep -iE "IFACE|bond0"
echo '----- 58 ------'
ssh 31.0.31.58 -p 10022 sar -n EDEV 1 1|grep -iE "IFACE|bond0"
echo '==============='
echo ''
echo '===== 51 ======'          
ssh 31.0.31.51 -p 10022 sar -n DEV 1 1|grep -iE "IFACE|bond0"
echo '----- 52 ------'
ssh 31.0.31.52 -p 10022 sar -n DEV 1 1|grep -iE "IFACE|bond0"
echo '----- 53 ------'
ssh 31.0.31.53 -p 10022 sar -n DEV 1 1|grep -iE "IFACE|bond0"
echo '----- 54 ------'
ssh 31.0.31.54 -p 10022 sar -n DEV 1 1|grep -iE "IFACE|bond0"
echo '----- 55 ------'
ssh 31.0.31.55 -p 10022 sar -n DEV 1 1|grep -iE "IFACE|bond0"
echo '----- 56 ------'
ssh 31.0.31.56 -p 10022 sar -n DEV 1 1|grep -iE "IFACE|bond0"
echo '----- 57 ------'
ssh 31.0.31.57 -p 10022 sar -n DEV 1 1|grep -iE "IFACE|bond0"
echo '----- 58 ------'
ssh 31.0.31.58 -p 10022 sar -n DEV 1 1|grep -iE "IFACE|bond0"
echo '==============='
echo ''
echo '===== 51 ======'
ssh 31.0.31.51 -p 10022 sar 1 1 | egrep -v ^$
echo '----- 52 ------'
ssh 31.0.31.52 -p 10022 sar 1 1 | egrep -v ^$
echo '----- 53 ------'
ssh 31.0.31.53 -p 10022 sar 1 1 | egrep -v ^$
echo '----- 54 ------'
ssh 31.0.31.54 -p 10022 sar 1 1 | egrep -v ^$
echo '----- 55 ------'
ssh 31.0.31.55 -p 10022 sar 1 1 | egrep -v ^$
echo '----- 56 ------'
ssh 31.0.31.56 -p 10022 sar 1 1 | egrep -v ^$
echo '----- 57 ------'
ssh 31.0.31.57 -p 10022 sar 1 1 | egrep -v ^$
echo '----- 58 ------'
ssh 31.0.31.58 -p 10022 sar 1 1 | egrep -v ^$
echo '==============='
echo ''
echo '==============='
ssh 31.0.31.51 -p 10022 uptime
ssh 31.0.31.52 -p 10022 uptime
ssh 31.0.31.53 -p 10022 uptime
ssh 31.0.31.54 -p 10022 uptime
ssh 31.0.31.55 -p 10022 uptime
ssh 31.0.31.56 -p 10022 uptime
ssh 31.0.31.57 -p 10022 uptime
ssh 31.0.31.58 -p 10022 uptime
echo '==============='
echo ''
echo '==============='
gccli -ugbase -pgbase@AQDY123 -e "select count(1) Max from hds.hx_pfsftcjrn;"
gccli -ugbase -pgbase@AQDY123 -e "select count(1) Tot from gbase.table_distribution;"
gccli -ugbase -pgbase@AQDY123 -e "select count(1) CuC from gbase.table_distribution where is_nocopies='NO' and isReplicate='YES'"
gccli -ugbase -pgbase@AQDY123 -e "select count(1) FuZ from gbase.table_distribution where is_nocopies='NO' and isReplicate='NO' and hash_column is null;"
gccli -ugbase -pgbase@AQDY123 -e "select count(1) Has from gbase.table_distribution where is_nocopies='NO' and isReplicate='NO' and hash_column is not null;"
gccli -ugbase -pgbase@AQDY123 -e "select count(1) noP from gbase.table_distribution where is_nocopies='YES';"
echo '==============='
echo ''
echo '==============='
ssh 31.0.31.51  -p 10022 ls -l /opt/gcluster/log/gcluster/system.log  | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.52  -p 10022 ls -l /opt/gcluster/log/gcluster/system.log  | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.53  -p 10022 ls -l /opt/gcluster/log/gcluster/system.log  | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.54  -p 10022 ls -l /opt/gcluster/log/gcluster/system.log  | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.55  -p 10022 ls -l /opt/gcluster/log/gcluster/system.log  | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.56  -p 10022 ls -l /opt/gcluster/log/gcluster/system.log  | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.57  -p 10022 ls -l /opt/gcluster/log/gcluster/system.log  | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.58  -p 10022 ls -l /opt/gcluster/log/gcluster/system.log  | awk '{print $5,$6,$7,$8"    : " $NF}'
echo '==============='
echo ''
echo '==============='
ssh 31.0.31.51  -p 10022 ls -l /opt/gnode/log/gbase/system.log        | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.52  -p 10022 ls -l /opt/gnode/log/gbase/system.log        | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.53  -p 10022 ls -l /opt/gnode/log/gbase/system.log        | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.54  -p 10022 ls -l /opt/gnode/log/gbase/system.log        | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.55  -p 10022 ls -l /opt/gnode/log/gbase/system.log        | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.56  -p 10022 ls -l /opt/gnode/log/gbase/system.log        | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.57  -p 10022 ls -l /opt/gnode/log/gbase/system.log        | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.58  -p 10022 ls -l /opt/gnode/log/gbase/system.log        | awk '{print $5,$6,$7,$8"    : " $NF}'
echo '==============='
echo ''
echo '==============='
ssh 31.0.31.51  -p 10022 ls -l /opt/gcluster/log/gcluster/express.log | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.52  -p 10022 ls -l /opt/gcluster/log/gcluster/express.log | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.53  -p 10022 ls -l /opt/gcluster/log/gcluster/express.log | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.54  -p 10022 ls -l /opt/gcluster/log/gcluster/express.log | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.55  -p 10022 ls -l /opt/gcluster/log/gcluster/express.log | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.56  -p 10022 ls -l /opt/gcluster/log/gcluster/express.log | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.57  -p 10022 ls -l /opt/gcluster/log/gcluster/express.log | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.58  -p 10022 ls -l /opt/gcluster/log/gcluster/express.log | awk '{print $5,$6,$7,$8"    : " $NF}'
echo '==============='
echo ''
echo '==============='
ssh 31.0.31.51  -p 10022 ls -l /opt/gnode/log/gbase/express.log       | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.52  -p 10022 ls -l /opt/gnode/log/gbase/express.log       | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.53  -p 10022 ls -l /opt/gnode/log/gbase/express.log       | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.54  -p 10022 ls -l /opt/gnode/log/gbase/express.log       | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.55  -p 10022 ls -l /opt/gnode/log/gbase/express.log       | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.56  -p 10022 ls -l /opt/gnode/log/gbase/express.log       | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.57  -p 10022 ls -l /opt/gnode/log/gbase/express.log       | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.58  -p 10022 ls -l /opt/gnode/log/gbase/express.log       | awk '{print $5,$6,$7,$8"    : " $NF}'
echo '==============='
echo ''
echo '==============='
ssh 31.0.31.51  -p 10022 ls -l /var/log/corosync.log       | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.52  -p 10022 ls -l /var/log/corosync.log       | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.53  -p 10022 ls -l /var/log/corosync.log       | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.54  -p 10022 ls -l /var/log/corosync.log       | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.55  -p 10022 ls -l /var/log/corosync.log       | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.56  -p 10022 ls -l /var/log/corosync.log       | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.57  -p 10022 ls -l /var/log/corosync.log       | awk '{print $5,$6,$7,$8"    : " $NF}'
ssh 31.0.31.58  -p 10022 ls -l /var/log/corosync.log       | awk '{print $5,$6,$7,$8"    : " $NF}'
echo '==============='
}

tny=`date +%Y-%m`
tyb > ${tny}.log
gccli -ugbase -pgbase@AQDY123 -vvv -e "select distinct(table_schema),count(1) table_count from information_schema.tables group by table_schema;" >> ${tny}.log 
gccli -ugbase -pgbase@AQDY123 -vvv -e "show processlist;" >> ${tny}.log


chmod 777 ${tny}.log
cp ${tny}.log /tmp/


