"""
Module for preparing inverted indexes based on uploaded documents
"""

import sys
import json
import re
from argparse import ArgumentParser, ArgumentTypeError, FileType
from io import TextIOWrapper
from typing import Dict, List

DEFAULT_PATH_TO_STORE_INVERTED_INDEX = "inverted.index"


class EncodedFileType(FileType):
    """File encoder"""

    def __call__(self, string):
        if string == "-":
            if "r" in self._mode:
                return TextIOWrapper(sys.stdin.buffer, encoding=self._encoding)
            if "w" in self._mode:
                return TextIOWrapper(sys.stdout.buffer, encoding=self._encoding)

            raise ValueError(f'argument "-" with mode {self._mode!r}')

        try:
            return open(string, self._mode, self._bufsize, self._encoding, self._errors)
        except OSError as exception:
            raise ArgumentTypeError(
                f"can't open '{string}': {exception}"
            )


class InvertedIndex:
    """
    Inverted index structure mapping words to document IDs
    """

    def __init__(self, words_ids: Dict[str, List[int]]):
        self.words_ids = words_ids

    def query(self, words: List[str]) -> List[int]:
        """Return list of documents containing all query words"""
        if not words:
            return []

        doc_sets = []

        for word in words:
            word_lower = word.lower()
            if word_lower not in self.words_ids:
                return []
            doc_sets.append(set(self.words_ids[word_lower]))

        result = set.intersection(*doc_sets) if doc_sets else set()
        return sorted(result)   #  FIXED

    def dump(self, filepath: str) -> None:
        """Save inverted index to file"""
        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(self.words_ids, f, ensure_ascii=False, indent=2)

    @classmethod
    def load(cls, filepath: str):
        """Load inverted index from file"""
        with open(filepath, 'r', encoding='utf-8') as f:
            words_ids = json.load(f)
        return cls(words_ids)


def load_documents(filepath: str) -> Dict[int, str]:
    """Load documents from file"""
    documents = {}

    with open(filepath, 'r', encoding='utf-8') as f:
        for line in f:
            if not line.strip():
                continue

            parts = line.split('\t', 1)
            if len(parts) != 2:
                continue

            doc_id = int(parts[0].strip())
            content = parts[1].strip()
            documents[doc_id] = content

    return documents


def build_inverted_index(documents: Dict[int, str]) -> InvertedIndex:
    """Build inverted index from documents"""
    words_ids: Dict[str, List[int]] = {}

    for doc_id, content in documents.items():
        content_lower = content.lower()
        words = re.split(r"\W+", content_lower)

        unique_words = set(words)  # keeps each word once per document

        for word in unique_words:
            if not word:
                continue

            if word not in words_ids:
                words_ids[word] = []

            words_ids[word].append(doc_id)

    return InvertedIndex(words_ids)


def callback_build(arguments) -> None:
    process_build(arguments.dataset, arguments.output)


def process_build(dataset, output) -> None:
    documents = load_documents(dataset)
    inverted_index = build_inverted_index(documents)
    inverted_index.dump(output)


def callback_query(arguments) -> None:
    process_query(arguments.query, arguments.index)


def process_query(queries, index) -> None:
    inverted_index = InvertedIndex.load(index)

    # Case 1: file input
    if hasattr(queries, 'read'):
        for line in queries:
            line = line.strip()
            if not line:
                continue

            query_words = line.split()
            print(line)
            print(",".join(map(str, inverted_index.query(query_words))))

    # Case 2: CLI input
    else:
        for query in queries:
            if isinstance(query, list):
                query_str = " ".join(query)
                print(query_str)
                print(",".join(map(str, inverted_index.query(query))))
            else:
                print(query)
                query_words = query.split()
                print(",".join(map(str, inverted_index.query(query_words))))


def setup_subparsers(parser) -> None:
    subparser = parser.add_subparsers(dest="command")

    build_parser = subparser.add_parser(
        "build",
        help="Build inverted index from dataset",
    )

    build_parser.add_argument(
        "-d", "--dataset",
        required=True,
        help="Path to dataset file"
    )

    build_parser.add_argument(
        "-o", "--output",
        default=DEFAULT_PATH_TO_STORE_INVERTED_INDEX,
        help="Output file for inverted index"
    )

    build_parser.set_defaults(callback=callback_build)

    query_parser = subparser.add_parser(
        "query",
        help="Query inverted index"
    )

    query_parser.add_argument(
        "--index",
        default=DEFAULT_PATH_TO_STORE_INVERTED_INDEX,
        help="Path to inverted index file"
    )

    group = query_parser.add_mutually_exclusive_group(required=True)

    group.add_argument(
        "-q", "--query",
        dest="query",
        action="append",
        nargs="+"
    )

    group.add_argument(
        "--query_from_file",
        dest="query",
        type=EncodedFileType("r", encoding="utf-8")
    )

    query_parser.set_defaults(callback=callback_query)


def main():
    parser = ArgumentParser(description="Inverted Index CLI tool")
    setup_subparsers(parser)

    args = parser.parse_args()

    if hasattr(args, "callback"):
        args.callback(args)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
