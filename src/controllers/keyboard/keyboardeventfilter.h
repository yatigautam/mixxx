#pragma once

#include <QEvent>
#include <QKeyEvent>
#include <QMultiHash>
#include <QObject>

#include "control/controlobject.h"
#include "preferences/configobject.h"

class ControlObject;

// This class provides handling of keyboard events.
class KeyboardEventFilter : public QObject {
    Q_OBJECT
  public:
    KeyboardEventFilter(ConfigObject<ConfigValueKbd> *pKbdConfigObject,
                        QObject *parent = nullptr, const char* name = nullptr);
    virtual ~KeyboardEventFilter();

    bool eventFilter(QObject* obj, QEvent* e);

    // Set the keyboard config object. KeyboardEventFilter does NOT take
    // ownership of pKbdConfigObject.
    void setKeyboardConfig(ConfigObject<ConfigValueKbd> *pKbdConfigObject);
    ConfigObject<ConfigValueKbd>* getKeyboardConfig();

  private:
    struct KeyDownInformation {
        KeyDownInformation(int keyId, int modifiers, ControlObject* pControl)
                : keyId(keyId),
                  modifiers(modifiers),
                  pControl(pControl) {
        }

        int keyId;
        int modifiers;
        ControlObject* pControl;
    };

    // Returns a valid QString with modifier keys from a QKeyEvent
    QKeySequence getKeySeq(QKeyEvent *e);

    // Run through list of active keys to see if the pressed key is already active
    // and is not a control that repeats when held.
    bool shouldSkipHeldKey(int keyId) {
        foreach (const KeyDownInformation& keyDownInfo, m_qActiveKeyList) {
            if (keyDownInfo.keyId == keyId && !keyDownInfo.pControl->getKbdRepeatable()) {
                return true;
            }
        }
        return false;
    }

    // List containing keys which is currently pressed
    QList<KeyDownInformation> m_qActiveKeyList;
    // Pointer to keyboard config object
    ConfigObject<ConfigValueKbd> *m_pKbdConfigObject;
    // Multi-hash of key sequence to
    QMultiHash<ConfigValueKbd, ConfigKey> m_keySequenceToControlHash;
};
