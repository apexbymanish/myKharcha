# Apple Featuring Nomination

Submit at **App Store Connect → your app → Featuring → Nominate your app**.
Apple's editorial team reads these. It is free, it takes twenty minutes, and
almost nobody submits one — which is exactly why it is worth doing first.

Submit **four to six weeks before** anything you want featured around, not after.

---

## What we are nominating for

Primary: **App Store feature / "New Apps We Love"** for the 1.0.3 release.
Secondary: **localisation** — the app ships in twenty languages, which is
unusual for an independent app and is a category Apple actively looks for.

## Short description (Apple asks for a paragraph)

Paisa Khoi? is a free expense tracker for people who do not want a
subscription, an advert, or an account. Paste a bank message, a receipt, or a
note and it reads the amount, the date and the category on device — no server
sees it. It works in any currency, converts foreign amounts as you paste them,
and is fully translated into twenty languages, including Nepali, Bengali,
Tamil, Telugu, Marathi and Urdu — languages most finance apps skip.

## What is new in this version

History became a chart you scroll through freely, where every bar carries its
own amount split into the categories the money went on, and tapping a day shows
what was actually bought. Reports was rebuilt around week, month and year, with
period comparison and your biggest day. Export now shows you exactly what it
contains before you share it.

## Why it deserves a feature

- **Free with no subscription, no advert and no account.** In a category built
  on paywalls, this one is not.
- **On-device parsing.** Paste a bank SMS; the amount and category are read
  without leaving the phone.
- **Twenty languages, any currency.** Built for people whose money is not in
  dollars and whose phone is not in English.
- **Private by default.** Data stays on the device unless you sign in with
  Apple to sync it.

## Accessibility

Worth stating explicitly; Apple weighs it.

- Every bar in the chart is its own VoiceOver element, labelled with its day and
  category and valued with its amount and direction.
- The chart exposes an `AXChartDescriptor`, so **Audio Graphs** can play a
  month's spending as pitch.
- Reduce Motion is honoured throughout.
- Dynamic Type is supported, with the layout reflowing at accessibility sizes.
- Colour is never the only carrier of meaning: every amount takes a `+` or `−`,
  and with Differentiate Without Color on, more category bands are named.
- Money colours are chosen for contrast (~4.5:1), not taken from system red and
  green, which fail on white.

## Localisation

Twenty in-app languages: Arabic, Bengali, German, English, Spanish, French,
Hindi, Indonesian, Japanese, Korean, Marathi, Nepali, Portuguese (Brazil),
Russian, Tamil, Telugu, Turkish, Urdu, Vietnamese, Simplified Chinese.
Twenty-two App Store locales. Right-to-left is supported for Arabic and Urdu.

## Links

- App Store: (fill in)
- Website: (fill in from `fastlane/metadata/en-US/marketing_url.txt`)
- Support: adhikari.manish21@gmail.com
