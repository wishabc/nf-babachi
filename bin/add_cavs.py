import pandas as pd
import argparse

def main(new_badmap, old_badmap, output):
    new_df = pd.read_table(new_badmap)
    old_df = pd.read_table(old_badmap)
    rs_ids = new_df['ID'].unique()
    imputed_cavs = old_df[~old_df['ID'].isin(rs_ids)]
    df = pd.concat([new_df, imputed_cavs])
    assert len(df.index) == len(old_df.index)
    df.to_csv(output, sep='\t', index=False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Add CAVs')
    parser.add_argument('-n', help='New BAD map file')
    parser.add_argument('-o', help='Old BAD map file')
    parser.add_argument('--output', help='Output file name')
    args = parser.parse_args()
    main(new_badmap=args.n, old_badmap=args.o, output=args.output)