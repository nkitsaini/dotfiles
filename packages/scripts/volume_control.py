#!/usr/bin/env python3
"""
requires wpctl (from wireplumber)
"""

from typing import cast
import re
from dataclasses import dataclass
import subprocess
import argparse
import enum
from typing import Literal

MAX_VOLUME = 2  # 200%

class ValidationError(Exception):
    pass

class VolumeChangeType(enum.Enum):
    ADD_STATIC = enum.auto()
    SUB_STATIC = enum.auto()
    ADD_PERCENT = enum.auto()
    SUB_PERCENT = enum.auto()

    @staticmethod
    def from_value(sign: Literal['+','-'], is_percent: bool):
        if not is_percent and sign == "+":
            return VolumeChangeType.ADD_STATIC
        elif not is_percent and sign == "-":
            return VolumeChangeType.SUB_STATIC
        elif is_percent and sign == "+":
            return VolumeChangeType.ADD_PERCENT
        elif is_percent and sign == "-":
            return VolumeChangeType.SUB_PERCENT
        else:
            raise Exception("Unreachable")
        

    def is_neg(self):
        return self in [VolumeChangeType.SUB_STATIC, VolumeChangeType.SUB_PERCENT]

    def is_static(self):
        return self in [VolumeChangeType.SUB_STATIC, VolumeChangeType.ADD_STATIC]


@dataclass
class VolumeChange:
    kind: VolumeChangeType 
    value: float

    @staticmethod
    def parse(value: str):
        pattern = re.compile(r"^(?P<sign>[+-])(?P<value>(\d|\.)+)(?P<percent>%?)$")
        match = pattern.fullmatch(value)
        if match is None:
            raise ValidationError(f"Invalid volume change: {value}")
        is_percent = match.group('percent') == "%"
        sign = cast(Literal['+', '-'], match.group('sign'))
        change_value = float(match.group('value'))
        
        type = VolumeChangeType.from_value(sign, is_percent)
        return VolumeChange(type, change_value)

    def apply(self, existing_volume: float):
        if self.kind.is_static():
            change = self.value
        else:
            change = existing_volume * (self.value)/100

        if self.kind.is_neg():
            return existing_volume - change
        else:
            return existing_volume + change
            
        
    


def set_volume(sink: str, value: float):
    subprocess.run(["wpctl", "set-volume", sink, str(value)], check=True)


def get_volume(sink: str) -> float:
    output = subprocess.run(
        ["wpctl", "get-volume", sink], check=True, stdout=subprocess.PIPE
    ).stdout.decode()
    assert "Volume: " in output
    return float(output.replace("Volume: ", "").strip())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("volume", type=str)
    parser.add_argument("-s", "--sink", default="@DEFAULT_AUDIO_SINK@")
    args = parser.parse_args()
    sink = args.sink
    volume: str = args.volume
    try:
        volume_change = VolumeChange.parse(volume)
    except ValidationError as e:
        print("Error:", e)
        return 1
        

    current_volume = get_volume(sink)
    print("> Current volume: ", current_volume)
    new_volume = volume_change.apply(current_volume)
    new_volume = min(new_volume, MAX_VOLUME)
    new_volume = max(new_volume, 0)
    new_volume = round(new_volume, 3)
    set_volume(sink, new_volume)
    print("> New volume: ", new_volume)

if __name__ == "__main__":
    exit(main())
