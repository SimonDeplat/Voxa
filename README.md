# Voxa

An audio effect interface including a resonator, an echo and a reverb, made with SuperCollider.

#### /!\ Warning /!\

This audio effect makes heavy usage of feedback. This is especially true for the 'resonance' effect. Even though companders and limters are internally used to limit the risk, setting high feedback amounts / high volume amplitudes can result in both internal and external larsens. Which might harm your ears (and break your speakers). As such, you should play at low volume until you get comfortable with the effect.

#### Installation

You will need `SuperCollider` to run this project. SuperCollider usage is beyond the scope of this documentation. [See this page to install SuperCollider](https://github.com/supercollider/supercollider).

You also need to install the `GraphicalModule` quark to run it. You can use the dedicated interface, or evaluate `Quarks.install("GraphicalModule");` to do so. Then you'll have to recompile the library (re-open SuperCollider or use `CTRL + SHIFT + L`).

If you had the GraphicalModule installed already, make sure it is up-to-date by evaluating `Quarks.update("GraphicalModule")`. Then, recompile.

To run Voxa, evaluate `Voxa.scd` within SuperCollider (once configured).

#### Usage

- Inputs interface allow you to specify which input channels are passed through the effect.

- To prevents larsens or unwanted sounds, a HPF, a LPF and a BRF are provided. Their frequencies can be specified, and they can be activated/deactivated.

- The resonance effect provides 9 distinct resonant frequencies, which are the 9 first harmonics of the specified main frequency (`freq`). Resonance is sent through the echo.

- The echo effect is controlled by a tap tempo button and further specified as a rythm decomposition (a quarter of a beat, a third of a beat, *etc*).

- The amount of dry signal can be specified independantly.

- The resulting mix (resonance + echo + dry) is sent through a simple stereo reverb.

- The master amp multiplies the signal, but also controls the threshold of a limiter to ensure signal is capped.

- A preset system allows to save the current software state, and to load it back.

#### Think about it

So there's 3 distinct effects: resonance, echo and reverb. However, all three have the same algorithm: delayed feedback loops. Funny when you think about it.
