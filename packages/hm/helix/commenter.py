import sys
import argparse


def is_line_commented(line: str, start_token: str, end_token: str):
    """Checks if a line is already a comment based on tokens."""
    stripped_line = line.strip()
    return stripped_line.startswith(start_token) and stripped_line.endswith(end_token)


def uncomment_line(line: str, start_token: str, end_token: str):
    """Removes comments from a line."""
    # Remove the start and end tokens while preserving any leading/trailing whitespace. Only a single space character after start token and single space character before end token should be removed and that too only if present.
    start_token_index = line.find(start_token)
    if line[start_token_index + len(start_token)] == " ":
        line = (
            line[:start_token_index] + line[start_token_index + len(start_token) + 1 :]
        )
    else:
        line = line[:start_token_index] + line[start_token_index + len(start_token) :]

    # find last index of end_token
    end_token_index = line.rfind(end_token)
    if line[end_token_index - 1] == " ":
        line = line[: end_token_index - 1] + line[end_token_index + len(end_token) :]
    else:
        line = line[:end_token_index] + line[end_token_index + len(end_token) :]

    return line


def comment_line(line, start_token, end_token):
    """Removes comments from a line."""
    # Find first none-space character
    first_char_index = 0
    while line[first_char_index].isspace():
        first_char_index += 1
    line = line[:first_char_index] + start_token + " " + line[first_char_index:]
    # Find last none-space character
    last_char_index = len(line) - 1
    while line[last_char_index].isspace():
        last_char_index -= 1
    line = line[: last_char_index + 1] + " " + end_token + line[last_char_index + 1 :]
    return line


def process_lines(content: str, start_token: str, end_token: str):
    lines = content.splitlines(keepends=True)
    output = ""

    should_comment = False
    # read all lines from stdin
    for line in lines:
        if line.isspace():
            continue
        if not is_line_commented(line, start_token, end_token):
            should_comment = True

    for line in lines:
        if line.isspace():
            output_line = line
        elif should_comment:
            if not is_line_commented(line, start_token, end_token):
                output_line = comment_line(line, start_token, end_token)
            else:
                output_line = line
        else:
            output_line = uncomment_line(line, start_token, end_token)
        output += output_line
        # print(output_line, end="")
    return output


def main():
    """Parses arguments and processes lines from stdin."""
    parser = argparse.ArgumentParser(
        description="Comment/uncomment lines based on tokens."
    )
    parser.add_argument(
        "--start-token",
        type=str,
        required=True,
        help="Token to mark the start of a comment.",
    )
    parser.add_argument(
        "--end-token",
        type=str,
        required=True,
        help="Token to mark the end of a comment.",
    )
    args = parser.parse_args()
    start_token: str = args.start_token
    end_token: str = args.end_token
    print(process_lines(sys.stdin.read(), start_token, end_token), end="")


def test():
    # commenting should work
    source = """
    console.log("Hello, World!") /* some inline comment */
    /* some commented line */

    """
    expected = """
    /* console.log("Hello, World!") /* some inline comment */ */
    /* /* some commented line */ */

    """
    assert process_lines(source, "/*", "*/") == expected
    assert process_lines(expected, "/*", "*/") == source


if __name__ == "__main__":
    # test()
    main()

