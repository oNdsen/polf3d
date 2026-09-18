# POLF 3D - Copyright (c) 2026 oNdsen. Licensed under the MIT License, see LICENSE.

# An example mod: copy it one folder up (mods/purple-interns.psd1) and start the game.
# A third of all guards are replaced by interns in purple hoodies: weaker, worth less, and chatty.
@{
    Name     = 'Purple interns'
    Enemies  = @{
        intern = @{
            BasedOn  = 'guard'
            HP       = 8, 10, 12, 12          # one number per difficulty
            Points   = 50
            Chase    = 0.03                   # a little faster than a guard
            Code     = 'i'                    # map makers can place one with i^ i> iv i< (in, iN ... as usual)
            Replaces = 'guard'; Share = 0.33
        }
    }
    Palettes = @{ intern = @{ Uniform = '7A3AA8'; UniformDark = '5A2A80'; Pants = '2A2A3A'; PantsDark = '1C1C28'; Hair = 'D8B040'; HatStyle = 'none' } }
    Voices   = @{
        intern       = 'It works on my machine!', 'Is this production?'
        'intern.die' = 'I will put it in a ticket.'
    }
    Weapons  = @{ pistol = @{ Name = 'Service pistol' } }
}
