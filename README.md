# zfs replica

クライアント側:

- zfsendsnap.rb を /etc/systemd/zfs/ に配置。
- 他の unit file を /etc/systemd/system/ に配置。

サーバ側:

- zfsrecvsnap.rb を /home/service/zfsrecvsnap/ に配置。
- 他の unit file を /etc/systemd/system/ に配置。

両側:
- zfsendsnap.rb を /etc/ に配置
  - 中身を確認
  - slack incoming webhook の URL を設定。

サーバ側の socket と クライアント側 timer を開始。
