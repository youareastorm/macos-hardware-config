#!/usr/bin/env python3
"""
usb-topology.py — pour chaque disque externe monté : sur quel hub il est, et son alimentation
(watt/mA) quand macOS la remonte.

Corrèle deux sources qui ne se recoupent pas nativement :
  - `diskutil list -plist external` donne le volume monté ("MUSIC 2To") et le nom d'appareil USB
    du disque physique ("MobileDataStar") — mais rien sur le hub ni l'alimentation.
  - `system_profiler -json SPUSBHostDataType` donne l'arbre bus/hub/appareil avec le nom d'appareil
    USB et USBDeviceKeyPowerAllocation quand disponible — mais pas le nom du volume monté.
Le nom d'appareil USB ("Device / Media Name" côté diskutil, "_name" côté system_profiler) est la
clé commune entre les deux.

Limite connue : un hub qui ne remonte ni nom ni PowerAllocation à macOS (ex. le boîtier multi-baies
sans firmware descriptif) reste identifié seulement par son idVendor/idProduct — voir "hub non nommé".

Usage : python3 usb-topology.py
"""

import json
import plistlib
import subprocess
import sys


def system_profiler_usb():
    out = subprocess.run(["system_profiler", "-json", "SPUSBHostDataType"], capture_output=True, timeout=30)
    return json.loads(out.stdout).get("SPUSBHostDataType", [])


def diskutil_external_disks():
    out = subprocess.run(["diskutil", "list", "-plist", "external"], capture_output=True, timeout=30)
    return plistlib.loads(out.stdout).get("AllDisksAndPartitions", [])


def diskutil_info(device_identifier):
    out = subprocess.run(["diskutil", "info", "-plist", device_identifier], capture_output=True, timeout=30)
    return plistlib.loads(out.stdout)


def index_usb_tree(nodes, hub_path, entries):
    """[(nom d'appareil USB, chemin de hubs, wattage ou None)], en descendant l'arbre bus/hub."""
    for node in nodes:
        name = node.get("_name", "Appareil sans nom")
        is_hub = "hub" in name.lower() or "bus" in name.lower()
        power = node.get("USBDeviceKeyPowerAllocation")
        if not is_hub:
            entries.append((name, hub_path, power))
        children = node.get("_items", [])
        if children:
            next_path = hub_path + [name] if is_hub else hub_path
            index_usb_tree(children, next_path, entries)


def find_device(entries, media_name):
    """`diskutil`'s media name ("MobileDataStar") est souvent un sous-ensemble tronqué du nom
    complet côté `system_profiler` ("Netac MobileDataStar") — correspondance par inclusion dans
    les deux sens plutôt qu'égalité stricte."""
    for name, hub_path, power in entries:
        if media_name in name or name in media_name:
            return hub_path, power
    return None, None


def mounted_volumes(disk_entry):
    names = []
    if disk_entry.get("VolumeName"):
        names.append(disk_entry["VolumeName"])
    for partition in disk_entry.get("Partitions", []):
        names.extend(mounted_volumes(partition))
    return names


def main():
    usb_nodes = system_profiler_usb()
    entries = []
    index_usb_tree(usb_nodes, [], entries)

    disks = diskutil_external_disks()
    if not disks:
        print("Aucun disque externe monté.")
        return

    for disk in disks:
        device_id = disk["DeviceIdentifier"]
        media_name = diskutil_info(device_id).get("MediaName", "?")
        if media_name == "Disk Image":
            continue  # image disque logicielle (ex. simulateur iOS), pas du vrai matériel USB
        volumes = mounted_volumes(disk) or ["(pas de volume monté)"]
        hub_path, power = find_device(entries, media_name)

        for volume in volumes:
            print(f"{volume}")
            print(f"  appareil USB : {media_name}")
            if hub_path is None:
                print("  hub : introuvable dans l'arbre USB (nom d'appareil non reconnu)")
            elif not hub_path:
                print("  hub : branché directement (pas de hub intermédiaire détecté)")
            else:
                print(f"  hub : {' -> '.join(hub_path)}")
            print(f"  alimentation : {power if power else 'non remontée par macOS'}")
            print()


if __name__ == "__main__":
    sys.exit(main())
