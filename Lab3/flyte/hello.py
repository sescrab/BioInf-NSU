import flyte

env = flyte.TaskEnvironment(name="hello_env")


@env.task
def say_hello() -> str:
    return "Hello, World!"


@env.task
def add_greeting(greeting: str, name: str = "Flyte") -> str:
    return f"{greeting} from {name}!"


@env.task
def print_message(message: str) -> str:
    print(f"[FLYTE OUTPUT] {message}")
    return message


@env.task
def hello_world_wf(name: str = "Flyte") -> str:
    greeting = say_hello()
    full_greeting = add_greeting(greeting=greeting, name=name)
    result = print_message(message=full_greeting)
    return result