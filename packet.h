// Copyright 2017 by Robert Evans (rrevans@gmail.com)
//
// This file is part of ubaboot.
//
// ubaboot is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// ubaboot is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with ubaboot.  If not, see <http://www.gnu.org/licenses/>.


// USB low speed requires 8 byte packets.
// Otherwise use maximum size packet allowed.
#ifdef USB_LOW_SPEED
#define MAX_PACKET 8
#else
#define MAX_PACKET 64
#endif
