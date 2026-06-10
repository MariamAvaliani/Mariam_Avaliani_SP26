# import time
from typing import List

Matrix = List[List[int]]


def task_1(exp: int):
    def power(base: int):
        return base ** exp

    return power


def task_2(*args, **kwags):
    for arg in args:
        print(arg)

    for value in kwags.values():
        print(value)


def helper(func):
    def wrapper(name):
        print("Hi, friend! What's your name?")
        func(name)
        print("See you soon!")

    return wrapper


@helper
def task_3(name: str):
    print(f"Hello! My name is {name}.")
import time

def timer(func):
    def wrapper(*args, **kwargs):
        start_time = time.time()

        result = func(*args, **kwargs)

        end_time = time.time()
        run_time = end_time - start_time

        print(f"Finished {func.__name__} in {run_time:.4f} secs")

        return result

    return wrapper


@timer
def task_4():
    return len([1 for _ in range(0, 10**8)])


def task_5(matrix: Matrix) -> Matrix:
    return [list(row) for row in zip(*matrix)]


def task_6(queue: str):
    count = 0

    for ch in queue:
        if ch == '(':
            count += 1
        elif ch == ')':
            count -= 1

        if count < 0:
            return False

    return count == 0
