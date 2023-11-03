# DNS-CURL-check-with-Jenkins

# 使用Jenkins進行DNS和CURL檢查

這是一個通過Jenkins運行腳本以檢查不同域名狀態的項目。

## 腳本

由Jenkins運行的主要腳本是：

- `check-dns-curl-final.sh`

該腳本從文本文件中獲取URL列表，對它們進行DNS查詢和HTTP狀態檢查。

## 域名列表

域名腳本 `urls.txt` 應該放置在Docker-compose配置的以下目錄中：
```
/root/domain-check/data/jenkins_configuration/urls.txt
```

## 日誌輸出

腳本運行的日誌存儲在：
```
/root/domain-check/data/jenkins_configuration/log


drwxr-xr-x 2 root root 4096 Nov 3 11:28 .
drwxr-xr-x 15 root root 4096 Nov 3 11:29 ..
-rw-r--r-- 1 root root 128 Nov 2 22:30 check_results_202311022230.log
-rw-r--r-- 1 root root 298 Nov 2 22:49 check_results_202311022249.log
-rw-r--r-- 1 root root 166 Nov 3 08:25 check_results_202311030825.log
```
