# Apple Featuring Nomination

Submit at **App Store Connect → your app → Featuring → Nominate your app**.
Apple's editorial team reads these. It is free, it takes twenty minutes, and
almost nobody submits one — which is exactly why it is worth doing first.

Submit **four to six weeks before** anything you want featured around, not after.

---

## Form answers — copy these

The nomination is a form, not a document. Only the two blocks below go into it;
everything under "Reference" is background for you.

**Type:** App Enhancements — new features and significant updates to an app that
is already live. Not "New Content" (that is for content, offers or events inside
an app) and not "App Launch" (the app has been on the store since 1.0.0).

**Name / title:**

```
History rebuilt as a scrollable spending chart
```

**Description** — 976 characters. **The field caps at exactly 1,000**, and
truncates silently at the limit rather than warning you, so keep any edit under
it.

```
Paisa Khoi? is a free expense tracker — no subscription, no ads, no account required.

This update rebuilds History into a full-screen chart you scroll freely through time. Every bar carries its own amount, split into the categories the money went on, and tapping a day shows the transactions behind it. Reports was rebuilt around Week, Month and Year, with period comparison and your biggest spending day.

What makes it unusual: paste a bank message, a receipt or a note and it reads the amount, date and category entirely on device — nothing is uploaded. It works in any currency, converting foreign amounts as you paste, and is fully translated into 20 languages including Nepali, Bengali, Tamil, Telugu and Urdu, which most finance apps skip.

Every bar in the chart is a VoiceOver element and the chart supports Audio Graphs. Reduce Motion and Dynamic Type are honoured, and no meaning is carried by colour alone.

Data stays on the device unless you sign in with Apple.
```

**Availability:** version 1.0.3, and the date it goes live. Submit the build for
review before finalising the nomination — the date has to be a real one.

### What not to paste

- The "why it deserves a feature" argument. It reads as pitching *at* the
  editors; the description should describe and let them decide.
- The full language list. The description names the ones that matter.
- Links. The form already knows which app this is.

---

# Reference

Background for filling in the **App Accessibility** label in the App Store
Connect sidebar, and for answering an editor who writes back asking for detail.

## Why it stands out

- **Free with no subscription, no advert and no account.** In a category built
  on paywalls, this one is not.
- **On-device parsing.** Paste a bank SMS; the amount and category are read
  without leaving the phone.
- **Twenty languages, any currency.** Built for people whose money is not in
  dollars and whose phone is not in English.
- **Private by default.** Data stays on the device unless you sign in with
  Apple to sync it.

## Accessibility

Enough detail to fill in the App Accessibility nutrition label, which is a
separate item in the App Store Connect sidebar and shows on the product page.

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
