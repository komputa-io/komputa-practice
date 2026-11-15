---
title: Sitrep Live
description: What Sitrep Live is, and where its docs live.
---

Sitrep Live is the dashboard that the practice's workers report to. Each worker session sends its state to one server. The server shows the whole fleet in one place: which session needs you, which one is stuck or failed, what the build did while you were away, and the open issues and pull requests of each project. You can answer a waiting session from the app, from herdr or from a phone. It guards each answer: you sign in first, and one answer goes to one wait.

The app and its code are in the `app/` folder of this repository. It runs on a private homelab host, behind a sign-in, so its docs are not on this site. They are a second site that the host serves with the app, at `/docs/` on the host's own address. A **?** icon in each view of the app opens the page that explains it.
