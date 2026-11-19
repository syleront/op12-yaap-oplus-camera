C=$(cat /sys/fs/selinux/class/service_manager/index); P=$(cat /sys/fs/selinux/class/service_manager/perms/find)
echo "class=$C findbit=$P"
for s in "u:r:priv_app_36:s0:c512,c768" "u:r:priv_app_36:s0" "u:r:platform_app:s0:c512,c768"; do
  exec 3<>/sys/fs/selinux/access; printf "%s u:object_r:vendor_hal_offlinecamera_service:s0 %s" "$s" "$C" >&3; read -r a <&3; exec 3>&-
  echo "$s -> $a"
done
