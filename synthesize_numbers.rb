#!/usr/bin/env ruby

=begin

= NSManagedObject の数値アクセッサを自動生成する

Authors::   GNUE(鵺)
Version::   1.0.1 2010-12-30 gnue
Copyright:: Copyright (C) gnue, 2010. All rights reserved.
License::   MIT ライセンスに準拠

　NSManagedObjectサブクラスのヘッダを読込んで数値型のアクセッサを自動生成します

== 使い方

$ synthesize_numbers.rb file...

- 入力ファイルにはヘッダファイルを指定します
- 入力ファイルが省略されたときは標準入力より入力を行います

生成された実装ファイル(.m) はそのままプロジェクトファイルに追加して使います

== ヘッダファイルへの記述

コメント行で @synthesize_numbers と @end を記述して生成する property を指定します

* カテゴリは省略可（括弧も省略すること）
* @property にコメントが記述されていると生成される実装ファイルにもコメントが追加されて読みやすくなります
* 元々の NSNumber の @property は必ず削除しておく必要があります（残ってるとメソッド名がぶつかる）

=== ヘッダファイル例

@interface Hogehoge :  NSManagedObject  
{
}

// @synthesize_numbers (カテゴリ)
@property (nonatomic, assign) int		prop1;		// 整数
@property (nonatomic, assign) double	prop2;		// 浮動小数点（倍精度）
@property (nonatomic, assign) float		prop3;		// 浮動小数点（単精度）
@property (nonatomic, assign) NSInteger prop4;		// 整数
@property (nonatomic, assign) long long prop5;		// 整数（64ビット）
@property (nonatomic, assign) BOOL		prop6;		// ブール値
// @end

@end

== TODO

* @property のコメントアウト対応。現在はコメントアウトしていてもアクセッサを生成してしまう
* データモデルのファイルから読込んでインターフェースと実装の両方を自動生成

== 開発履歴

* 1.0.1 2010-12-30
  * 引数がないときは Usage を出すようにした
* 1.0 2010-11-04
  * とりあえず作ってみた

=end


class ManagedObjectProperty
	def initialize(type, name, comment = nil)
        @type = type
        @name = name
		@comment = comment
	end

	def interface(type = @type, name = @name, comment = @comment)
		# プロパティ宣言の生成
		comment = "\t" + comment if comment
		"@property (nonatomic, assign) #{type} #{name};#{comment}\n"
	end

	def capitalize(str)
		# 先頭文字のみ大文字にして後ろは変更しない
		str.gsub(/^./) { $&.upcase }
	end

	def primitiveAccessors(type = @type, name = @name, comment = @comment)
		# プライベートアクセッサの生成
		capName = capitalize(name)
		comment = "\n" + comment if comment

		<<EOS
#{comment}
- (NSNumber *)primitive#{capName};
- (void)setPrimitive#{capName}:(NSNumber *)value;
EOS
	end

	def getterType(type = @type)
		# NSNumber の getter に対応する名前に変換する
		getterType = type

		case type
		when 'NSInteger'
			getterType = 'integer'
		when 'BOOL'
			getterType = 'bool'
		when /long\s+long/
			getterType = 'longLong'
		else
			getterType = type
		end

		getterType
	end

	def implementation(type = @type, name = @name, comment = @comment)
		# 実装の生成
		getType = getterType(type)
		setType = capitalize(getType)
		capName = capitalize(name)
		comment = "\n" + comment if comment

		<<EOS
#{comment}
- (#{type})#{name}
{
    NSNumber * tmpValue;
    
    [self willAccessValueForKey:@"#{name}"];
    tmpValue = [self primitive#{capName}];
    [self didAccessValueForKey:@"#{name}"];
    
    return [tmpValue #{getType}Value];
}

- (void)set#{capName}:(#{type})value 
{
    [self willChangeValueForKey:@"#{name}"];
    [self setPrimitive#{capName}:[NSNumber numberWith#{setType}:value]];
    [self didChangeValueForKey:@"#{name}"];
}
EOS
	end
end



class PropertyGenerator
	def initialize(suffix = "NumberAccessors")
		@suffix = suffix
		@category = "CoreDataGeneratedNumberAccessors"
		@propertyList = []
	end

	def append(type, name, comment = nil)
		# プロパティを追加
		@propertyList << ManagedObjectProperty.new(type, name, comment)
	end

	def printHeader(file, className = @className, category = @category)
		# ヘッダ
		file.print "@interface #{className} (#{category})\n", "\n"
		@propertyList.each { |mo| file.print mo.interface }
		file.print "\n", "@end\n"
	end

	def printPrimitiveAccessors(file, className = @className, category = @category)
		# プライベートアクセッサ
		file.print "@interface #{className} (CoreDataGeneratedPrimitiveAccessors)\n"
		@propertyList.each { |mo| file.print mo.primitiveAccessors }
		file.print "\n", "@end\n"
	end

	def printImplementation(file, className = @className, category = @category)
		# 実装
		file.print "@implementation #{className} (#{category})\n", "\n"
		@propertyList.each { |mo| file.print mo.implementation, "\n" }
		file.print "\n", "@end\n"
	end

	def save(fname = @className+'.h')
		base = File.basename(fname, '.*') + @suffix

=begin
		# ヘッダファイルを保存
		if @category then
			File.open("#{base}.h", 'w+') { |f|
				printHeader(f)
			}
		end
=end

		# 実装ファイルを保存
		File.open("#{base}.m", 'w+') { |f|
			f.print "#import \"#{fname}\"\n", "\n\n"
			printPrimitiveAccessors(f)
			f.print "\n\n"
			printImplementation(f)
		}
	end

	def ganerate(file = $stdin, path = nil)
		on = false
		fname = File.basename(path) if path

		file.each { |line|
			case line
			when /@synthesize_numbers\s*(\(\s*(.+)\s*\))?/
				# 生成フラグをonにする
				@category = $2 if $2
				on = true
			when /@end\s*/
				# 生成フラグをoffにする
				on = false
			when /@interface\s*(\w+)\s*/
				# クラス名を設定
				@className = $1
			when /@property\s*\(.+\)\s*(\w+(\s*\w+)?)\s+(\w+)[^\/]*(\/\/.+)?/
				# プロパティを追加
				append($1, $3, $4) if on
			end
		}

		save(fname)
	end
end


if ARGV.length == 0
	cmd = File.basename $0
	print "Usage: #{cmd} file...\n"
	exit
end


mos = PropertyGenerator.new

ARGV.each { |path|
	File.open(path) { |f| mos.ganerate(f, path) }
}
