import struct

def write_varlen(val):
    buf = []
    buf.append(val & 0x7F)
    val >>= 7
    while val > 0:
        buf.append((val & 0x7F) | 0x80)
        val >>= 7
    buf.reverse()
    return bytes(buf)

def create_midi_file(filepath, notes_with_duration, division=480, tempo_bpm=120):
    """
    notes_with_duration is list of (pitch, duration_in_ticks, rest_after_ticks)
    """
    tempo_us_per_beat = int(60_000_000 / tempo_bpm)
    track_data = bytearray()
    
    # Set Tempo event at delta 0: FF 51 03 tt tt tt
    track_data.extend(write_varlen(0))
    track_data.extend(bytes([0xFF, 0x51, 0x03, 
                            (tempo_us_per_beat >> 16) & 0xFF,
                            (tempo_us_per_beat >> 8) & 0xFF,
                            tempo_us_per_beat & 0xFF]))
    
    # Add Note events
    for pitch, dur, rest in notes_with_duration:
        # Note On (delta 0, note, vel 100)
        track_data.extend(write_varlen(0))
        track_data.extend(bytes([0x90, pitch, 100]))
        
        # Note Off (delta = dur, note, vel 0)
        track_data.extend(write_varlen(dur))
        track_data.extend(bytes([0x80, pitch, 0]))
        
        if rest > 0:
            # We will insert rest before next note by making next note's delta = rest
            pass
            
    # Clean track structure with exact deltas
    track_data_clean = bytearray()
    # Tempo at delta 0
    track_data_clean.extend(write_varlen(0))
    track_data_clean.extend(bytes([0xFF, 0x51, 0x03, 
                                  (tempo_us_per_beat >> 16) & 0xFF,
                                  (tempo_us_per_beat >> 8) & 0xFF,
                                  tempo_us_per_beat & 0xFF]))
    
    pending_delta = 0
    for pitch, dur, rest in notes_with_duration:
        # Note On after pending_delta
        track_data_clean.extend(write_varlen(pending_delta))
        track_data_clean.extend(bytes([0x90, pitch, 100]))
        
        # Note Off after dur
        track_data_clean.extend(write_varlen(dur))
        track_data_clean.extend(bytes([0x80, pitch, 0]))
        
        pending_delta = rest
        
    # End of Track: delta pending_delta, FF 2F 00
    track_data_clean.extend(write_varlen(pending_delta))
    track_data_clean.extend(bytes([0xFF, 0x2F, 0x00]))
    
    # Header: MThd, length=6, format=0, tracks=1, division
    header = struct.pack(">4sIHHH", b"MThd", 6, 0, 1, division)
    track_chunk = struct.pack(">4sI", b"MTrk", len(track_data_clean)) + track_data_clean
    
    with open(filepath, "wb") as f:
        f.write(header)
        f.write(track_chunk)
    print(f"Generated {filepath} ({len(header) + len(track_chunk)} bytes)")

# 1. Bach Toccata in D Minor (Iconic opening)
# A4=69, G4=67, A4=69 ...
bach_notes = [
    (69, 120, 30),  # A4
    (67, 120, 30),  # G4
    (69, 480, 240), # A4 (fermata)
    (67, 120, 30),  # G4
    (65, 120, 30),  # F4
    (64, 120, 30),  # E4
    (62, 480, 240), # D4 (fermata)
    (61, 480, 120), # C#4
    (62, 960, 480), # D4
    # Lower octave run
    (57, 120, 30),  # A3
    (55, 120, 30),  # G3
    (57, 480, 240), # A3
    (55, 120, 30),  # G3
    (53, 120, 30),  # F3
    (52, 120, 30),  # E3
    (50, 480, 240), # D3
    (49, 480, 120), # C#3
    (50, 960, 480)  # D3
]
create_midi_file("c:/Antigravity/teslacoil/sample_midis/Bach_Toccata.mid", bach_notes, division=480, tempo_bpm=100)

# 2. Super Mario Bros (Main Theme snippet)
# E5, E5, rest, E5, rest, C5, E5, rest, G5, rest, G4
mario_notes = [
    (76, 120, 60),  # E5
    (76, 120, 180), # E5
    (76, 120, 180), # E5
    (72, 120, 60),  # C5
    (76, 240, 120), # E5
    (79, 360, 240), # G5
    (67, 360, 240), # G4
    (72, 240, 180), # C5
    (67, 240, 180), # G4
    (64, 240, 180), # E4
    (69, 180, 60),  # A4
    (71, 180, 60),  # B4
    (70, 180, 60),  # Bb4
    (69, 240, 120)  # A4
]
create_midi_file("c:/Antigravity/teslacoil/sample_midis/Mario_Theme.mid", mario_notes, division=480, tempo_bpm=180)

# 3. Fur Elise (Theme snippet)
elise_notes = [
    (76, 120, 30), # E5
    (75, 120, 30), # D#5
    (76, 120, 30), # E5
    (75, 120, 30), # D#5
    (76, 120, 30), # E5
    (71, 120, 30), # B4
    (74, 120, 30), # D5
    (72, 120, 30), # C5
    (69, 360, 120),# A4
    (60, 120, 30), # C4
    (64, 120, 30), # E4
    (69, 120, 30), # A4
    (71, 360, 120),# B4
    (64, 120, 30), # E4
    (68, 120, 30), # G#4
    (71, 120, 30), # B4
    (72, 360, 120) # C5
]
create_midi_file("c:/Antigravity/teslacoil/sample_midis/Fur_Elise.mid", elise_notes, division=480, tempo_bpm=130)
