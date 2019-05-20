# FM7 physical interface design, who controls what?

**There are four things**

1. Arc
2. Grid
3. OLED
4. Norns keys + encoders

The first iteration had the grid controlling the Arc to tell which encoder should be dynamically bound to what parameter in Norns. The enable flow goes like

1. Toggle grid key on
1. Pick first available Arc ring
1. Get parameter value
1. Write to Arc LED ring
1. On encoder rotation, update parameter and light arc LEDs

The disable flow goes like

1. Toggle grid off
1. look up which ring this toggle claimed
1. clear the LEDs on that ring

This works fine. Now we add another set of complexity to the mix. 

There is a grid display on the OLED that shows a number, rounded up to the nearest integer of the value for that phase mod parameter. The grid also shows the same representation of which encoders are enabled by illuminating the square equal to the grid key coordinates. The utility of this shows the user roughly all the parameter values in the whole mod matrix. Previously this information was hidden behind three menus.

The flow is similar to the first but adds some new steps to arc rotation

1. get param value
1. Round up to nearest int
1. update OLED with this value
1. update parameter value and light arc LEDs

This is tricky because 4 of these values can be updated at once, based on which encoders are active. The values should be stored in a table and the screen update function called on each encoder delta.

The current table name for the screen is named "mods", I think. It might be a mess. Basically, it can be collapsed into a vector like the toggles vector and each value can be an int in the range 0-6.

## Frequency shift

In the frequency ratios of each operator significantly effect the harmonics in the sound. There are some ratios that are more "musical" than others. There are far fewer musical ratios than "noisy" values. Both are important and the UI gives the performer the option to choose either a free floating value or a quantized value. In frequency shift mode, Norns encoders 2 and 3 are free and quantized, respectively. Pressing the corresponding key on the grid enables these encoders to operate in frequency ratio mode. The process. 

1. Press and hold button on grid
2. assign encoder 2 to frequency control
3. get param value from that op ratio
4. Update OLED square with value
5. set param value delta when encoder is moved
6. round value to 2 decimal places
7. Draw new value on OLED

