from typing import List


def task_1(array: List[int], target: int) -> List[int]:
    seen = set()

    for number in array:
        needed = target - number

        if needed in seen:
            return [needed, number]

        seen.add(number)

    return []


def task_2(number: int) -> int:
    sign = 1

    if number < 0:
        sign = -1
        number = -number

    result = 0

    while number > 0:
        digit = number % 10
        result = result * 10 + digit
        number = number // 10

    return sign * result

def task_3(array: List[int]) -> int:
    for number in array:
        index = abs(number) - 1

        if array[index] < 0:
            return abs(number)

        array[index] = -array[index]

    return -1


def task_4(string: str) -> int:
    values = {
        "I": 1,
        "V": 5,
        "X": 10,
        "L": 50,
        "C": 100,
        "D": 500,
        "M": 1000,
    }

    result = 0

    for i in range(len(string)):
        if i + 1 < len(string) and values[string[i]] < values[string[i + 1]]:
            result -= values[string[i]]
        else:
            result += values[string[i]]

    return result

def task_5(array: List[int]) -> int:
    smallest = array[0]

    for num in array:
        if num < smallest:
            smallest = num

    return smallest
