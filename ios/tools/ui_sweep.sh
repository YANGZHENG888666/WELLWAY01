#!/bin/bash
# 全页面截图巡检：把 App 里所有 `-flag` 调试入口在 Pro / SE 两台模拟器上各截一遍图，
# 用来看有没有回归、SE 上有没有裁切。改动涉及公共组件（Tab 栏、底部主按钮、页头、弹窗）
# 之后跑一遍，比只翻改动的页面可靠。
#
# 用法:
#   ios/tools/ui_sweep.sh                 # 默认 Pro + SE，输出到 /tmp/ui-sweep
#   OUT=/tmp/x DEVICES="pro" ios/tools/ui_sweep.sh
#
# 注意:
# 1. 有些 flag 是「修饰符」，单跑只会落到首页，必须带上父级入口：
#      -badgesample/-badgesempty → -badges
#      -badgelocked              → -badgedetail
#      -vehicleactions           → -vehicles -vehiclesample
#      -vehiclephoto / -vehiclephotopicked / -vehiclephotosaving → -vehicles -vehiclesample
#      -notificationsempty/-notifsample → -notifications
#      -teamrows/-teamdenied/-teamfailed → -team
#      -routesempty/-routeserror/-routesfilterempty → -routes
#      -settingsnotifyoff/-settingsnotifydialog → -settings
#      -feedbackerror → -feedback
#      -agreement-bottom → -agreement-user
#      -departexpanded/-departbottom/-departlate/-departdatafail → -depart
#      -record* / -recordsempty  → -records
#      -summaryfailed/-summarynotrack/-summarytrack → -summary
#      -focusotp                 → -emailbind
#      -mapchoice                → -riding
#      -ridingpaused / -ridingending → -riding
#      -profilebottom            → -profile
#      -accountdeleting          → -profile
#      -recordsbottom / -notificationsbottom 同理，分别必须带父级入口
#      -ridersloading            → -team（骑手统计 Tab；-riders 是路线内的骑手页）
#      -routemapfull             → -routedetail
#      -vehicledeleting          → -vehicles -vehiclesample
# 2. 车库四个底部弹窗（车辆详情 / 油价 / 天气 / 路况）是代码里 4.5s 后才展开的，
#    油价/天气失败态也必须带父级入口（-fuel -fuelerror / -weathersheet -weathererror）；
#    这段用 8s 等待，否则只能截到首页。
set -u

OUT="${OUT:-/tmp/ui-sweep}"
PRO="${PRO:-DA0842EB-8310-4D5D-BD59-D4E7351871E2}"
SE="${SE:-4F694261-DBE6-49E4-9799-3A250BA1E4C6}"
BUNDLE="com.wellway.WELLWAY"
WAIT="${WAIT:-3.2}"
SLOW_WAIT="${SLOW_WAIT:-8}"

PAGES=(
  -about -addvehicle -addvehicleselected -agreement -arrival -badgedetail -badgeearned
  -badges -depart -departdraftdemo -departinfo -destinationpicker -dialogdemo -emailbind -feedback -forgot -gallery
  -garageempty -garageskeleton -guest -login -loginsuccess -mapswitch -navchoice
  -networkerror -notifications -pagenumbers -passwordlogin -picker -pickermodels
  -profile -profilepage -recorddetail -records -riders -riding -routedetail
  -routedetailpicker -routes
  -settings -sharecard -signup -summary -team -tiltdemo -toastdemo -vehicles
  -vehicleswitch
)

COMBOS=(
  "-badges -badgesample"
  "-badges -badgesempty"
  "-badgedetail -badgelocked"
  "-navchoice -navchoice-far"
  "-navchoice -navchoice-confirm"
  "-navchoice -navchoice-locationerror"
  "-team -ridersloading"
  "-routedetail -routemapfull"
  "-vehicles -vehiclesample -vehicleactions"
  "-vehicles -vehiclesample -vehiclephoto"
  "-vehicles -vehiclesample -vehicledeleting"
  "-vehicles -vehiclesample -vehiclephoto -vehiclephotopicked"
  "-vehicles -vehiclesample -vehiclephoto -vehiclephotosaving"
  "-notifications -notificationsempty"
  "-notifications -notifsample"
  "-notifications -notifsample -notificationsbottom"
  "-team -teamrows"
  "-team -teamdenied"
  "-team -teamfailed"
  "-routes -routesempty"
  "-routes -routeserror"
  "-picker -pickerbrandempty"
  "-picker -pickerpinyin"
  "-pickermodels -pickermodelempty"
  "-settings -settingsnotifyoff"
  "-settings -settingsnotifydialog"
  "-settings -settingsbottom"
  "-feedback -feedbackerror"
  "-agreement-user -agreement-bottom"
  "-depart -departexpanded"
  "-depart -departbottom"
  "-depart -departlate"
  "-depart -departdatafail"
  "-records -recordcompleted"
  "-records -recordridingsample"
  "-records -recordfirst"
  "-records -recordsempty"
  "-records -recordtrackpreview"
  "-records -recordsbottom"
  "-profile -accountdeleting"
  "-summary -summaryfailed"
  "-summary -summarynotrack"
  "-summary -summarylost"
  "-summary -summarytrack"
  "-emailbind -focusotp"
  "-riding -mapchoice"
  "-riding -ridingpaused"
  "-riding -ridingending"
)

SLOW=( -arrival )
SLOW_COMBOS=(
  "-garagesample -vehicledetail"
  "-garagesample -fuel"
  "-garagesample -weathersheet"
  "-garagesample -trafficsheet"
  "-garagesample -fuel -fuelerror"
  "-garagesample -weathersheet -weathererror"
  "-routes -routesfilterempty"
  # 「我的」页尾依赖骑行合计异步加载后再定位，3.2 秒会截到第一次滚动的中间态
  "-profile -profilebottom"
  "-guest -profile -profilebottom"
)

shoot() {
  local dev="$1" dir="$2" name="$3" wait="$4"; shift 4
  xcrun simctl terminate "$dev" "$BUNDLE" >/dev/null 2>&1
  xcrun simctl launch "$dev" "$BUNDLE" "$@" >/dev/null 2>&1
  sleep "$wait"
  xcrun simctl io "$dev" screenshot "$dir/$name.png" >/dev/null 2>&1
  echo "  $name"
}

DEVICES="${DEVICES:-pro se}"
for key in $DEVICES; do
  case "$key" in
    pro) dev="$PRO" ;;
    se)  dev="$SE" ;;
    *) echo "未知设备 $key"; exit 1 ;;
  esac
  dir="$OUT/$key"
  mkdir -p "$dir"
  echo "== $key =="
  for f in "${PAGES[@]}"; do
    shoot "$dev" "$dir" "${f#-}" "$WAIT" "$f"
  done
  for f in "${SLOW[@]}"; do
    shoot "$dev" "$dir" "${f#-}" "$SLOW_WAIT" "$f"
  done
  for c in "${SLOW_COMBOS[@]}"; do
    name=$(echo "$c" | tr " " "_" | sed "s/-//g")
    shoot "$dev" "$dir" "$name" "$SLOW_WAIT" $c
  done
  for c in "${COMBOS[@]}"; do
    name=$(echo "$c" | tr ' ' '_' | sed 's/-//g')
    shoot "$dev" "$dir" "$name" "$WAIT" $c
  done
done
echo "截图目录: $OUT"
