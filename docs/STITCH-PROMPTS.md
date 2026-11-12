# WELLWAY × Google Stitch 提示词

Stitch 只支持英文界面，提示词用英文效果最好。一次只描述**一屏**，选 **Mobile**。

---

## 1. 车库首页（主用）

```
Design one mobile screen for a motorcycle riding app called WELLWAY. This is the garage home screen.

Pure black background (#0A0A0B). At the top left a small white title 车库, and a + icon on
the right. Below it, one large motorcycle photo centred, taking about half of the screen,
softly lit from above with a faint halo so it separates from the black.

Under the photo: a small uppercase grey label CFMOTO with wide letter spacing, and directly
below it a large 33pt title 450 SR in warm off-white (#F2EFE9).

Then a 1px hairline divider (#1F1F21). Then one row of three columns: 8.75 km distance,
晴 15° weather, 拥堵 traffic. Each column has a 20pt number on top and a 9.5pt grey label
underneath.

Another hairline. Then a small label 上次骑行, a large 198.32 km, and three small stats in a
row: 耗时 05:35:18, 极速 102 km/h, 平均 60.5 km/h.

At the bottom a full-width off-white button that says 看看路线, then a minimal dark tab bar
with five thin 1.5px line icons, the first one active in white.

Overall feeling: dark, quiet, editorial, automotive showroom. No cards, no rounded boxes
around the bike, no gradients except the soft light behind the bike, no emoji, no badge
labels, no English micro-copy.
```

---

## 2. 路线列表

```
Design one mobile screen: a route list for the same motorcycle app. Pure black background.
Small white title 路线 at top left. Below it a vertical list of six route rows. Each row is
a 16:9 thumbnail photo of a mountain road on the left and on the right two lines: a 15pt
white route name and a 11pt grey province/city label. Rows are separated by 1px hairlines,
no cards, no rounded corners, no shadows. Thumbnails have a slight desaturation. Same dark
minimal tab bar at the bottom.
```

---

## 3. 出发页

```
Design one mobile screen: the depart screen of the same app. Pure black background. Small
title 出发 at top left. A large 33pt headline showing the destination city. Under it three
plain rows without cards, separated by hairlines: 距离 8.75 km, 天气 晴 15°, 路况 拥堵 —
each row is a 10px grey label on the left and a 15px warm-white value right-aligned. Then a
weather strip with an hourly forecast. At the bottom a full-width off-white button 开始骑行.
Dark minimal tab bar. Quiet, editorial, no cards, no emoji.
```

---

## 使用要点

1. 一次只生成一屏，别在一条提示里塞 5 个页面。
2. 生成后不满意，用 **Edit with prompt** 局部改："make the bike larger, remove the card border"。
3. 右上角可以 **Export to Figma**，导出的 Auto Layout 是可直接改的结构。
4. 它默认会加一些你没要的东西（badge、小标签、彩色图标），提示词最后一句务必写
   `no badges, no emoji, no English micro-copy`。
