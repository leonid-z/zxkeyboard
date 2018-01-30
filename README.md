# zxkeyboard

ZX-Spectrum PS/2 Keyboard Adapter based on microcontroller and CPLD
===================================================================

The idea of project is simple.

CPLD has 40 bit register 'Kn' releated to KAn lines of original ZX keyboard. Outputs 'KDn' are result logical function from 'KAn' and 'Kn'.
Microcontroller (MC) reads PS/2 keyboard codes and update CPLD 40 bit register.

The next project development is following:
-- programming CPLD via MC;
-- USB keyboard using (it will be required USB host controller)


Note: look at http://www.avray.ru/ru/zx-spectrum-ps2-keyboard/ as well