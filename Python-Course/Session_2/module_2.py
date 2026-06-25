# from collections import defaultdict as dd
# from itertools import product
from typing import Any, Dict, List, Tuple


def task_1(data_1: Dict[str, int], data_2: Dict[str, int]):
    result = data_1.copy()

    for key, value in data_2.items():
        if key in result:
            result[key] += value
        else:
            result[key] = value

    return result


def task_2():
    result = {}

    for i in range(1, 16):
        result[i] = i * i

    return result


def task_3(data: Dict[Any, List[str]]):
    result = [""]

    for key in data:
        temp = []

        for letter in data[key]:
            for combo in result:
                temp.append(combo + letter)

        result = temp

    return result

def task_4(data: Dict[str, int]):
    sorted_items = sorted(data.items(), key=lambda x: x[1], reverse=True)

    result = []

    for i in range(min(3, len(sorted_items))):
        result.append(sorted_items[i][0])

    return result

def task_5(data: List[Tuple[Any, Any]]) -> Dict[str, List[int]]:
    result = {}

    for key, value in data:
        if key in result:
            result[key].append(value)
        else:
            result[key] = [value]

    return result


def task_6(data: List[Any]):
    result = []
    seen = set()

    for item in data:
        if item not in seen:
            result.append(item)
            seen.add(item)

    return result

def task_7(words: [List[str]]) -> str:
    if not words:
        return ""

    prefix = words[0]

    for word in words[1:]:
        while not word.startswith(prefix):
            prefix = prefix[:-1]

            if not prefix:
                return ""

    return prefix


def task_8(haystack: str, needle: str) -> int:
    if needle == "":
        return 0

    n = len(haystack)
    m = len(needle)

    for i in range(n - m + 1):
        if haystack[i:i + m] == needle:
            return i

    return -1