# The Luna Sync Shortcut

Built by hand in the Shortcuts app on the iPhone, once. `URL` and `KEY` are the database URL and anon key from the setup link (never commit them). Every request carries two headers: `apikey: KEY` and `Authorization: Bearer KEY`.

Related: [luna.md](luna.md).

## Shortcut "Luna Sync"

1. **Get Contents of URL**: `URL/rest/v1/records?kind=eq.sleep.sample&select=data&order=data->>e.desc&limit=1`, method GET, the two headers.
2. **Get Item from List**: First Item of *Contents of URL*. **Get Dictionary Value**: `data` of it. **Get Dictionary Value**: `e` of that. Rename the result to *Last*.
3. **If** *Last* has any value: **Adjust Date**: subtract 12 hours from *Last*. **Otherwise**: **Adjust Date**: subtract 14 days from *Current Date*. **End If**. **Set Variable** *Since* to *If Result*.
4. **Find Health Samples** where Type is Sleep Analysis and Start Date is after *Since*, sorted by Start Date, no limit. **Repeat with Each**:
   - **Format Date** *Start Date* of *Repeat Item* as ISO 8601 with time → *S*. **Format Date** *End Date* → *E*.
   - **Text**: `{"kind":"sleep.sample","id":"<Value>|<S>|<Source>","data":{"s":"<S>","e":"<E>","v":"<Value>"}}` where Value and Source are the Repeat Item's details.
   - **Add to Variable** *Rows*.
5. **Find Health Samples** where Type is Heart Rate and Start Date is after *Since*. **Repeat with Each**: **Format Date** *Start Date* with custom format `H` → *Hour*. **If** *Hour* is greater than 19, or (second If) less than 11: same Text as above with `"v":"HR","q":"<Value>"` and id `HR|<S>|<Source>`, **Add to Variable** *Rows*.
6. **Find Health Samples** where Type is Heart Rate Variability and Start Date is after *Since*. **Repeat with Each**: Text with `"v":"HRV","q":"<Value>"` and id `HRV|<S>|<Source>`, **Add to Variable** *Rows*.
7. **If** *Rows* has any value: **Combine Text** *Rows* with Custom `,`. **Text**: `[` *Combined Text* `]`. **Get Contents of URL**: `URL/rest/v1/records?on_conflict=user_id,kind,id`, method POST, the two headers plus `Content-Type: application/json` and `Prefer: resolution=merge-duplicates`, Request Body File = that Text.

## Automation

Shortcuts → Automation → New → **Alarm** → Is Stopped (the wake-up alarm) → Run Immediately → Luna Sync. Add a second one for **App** → Luna opened or a first unlock trigger if wanted. Health is readable only once the phone is unlocked, which these triggers guarantee.

## From the web app

The sync button opens `shortcuts://x-callback-url/run-shortcut?name=Luna%20Sync&x-success=<Luna url>#synced`; Shortcuts returns to Luna when it finishes, and Luna pulls and shows how many nights are new.
