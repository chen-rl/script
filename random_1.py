import random
import string

def random_string(length):
    """生成随机字符串"""
    letters = string.ascii_letters
    return ''.join(random.choice(letters) for i in range(length))

def generate_phone_number():
    """生成随机电话号码"""
    return '1' + ''.join(random.choice('0123456789') for _ in range(10))

def generate_email():
    """生成随机邮箱"""
    username = random_string(8)
    domain = random.choice(['gmail.com', 'yahoo.com', 'hotmail.com'])
    return f"{username}@{domain}"

def generate_data_line():
    """生成一行数据"""
    surname = random_string(3)
    given_name = random_string(3)
    phone = generate_phone_number()
    email = generate_email()
    # s9 contact add familyName=柴 givenName=祥 phoneNumber=11802645654 email=qweqw@qq.com
    return f"s9 contact add familyName={surname} givenName={given_name} phoneNumber={phone} email={email}\n"

def generate_data_file(filename, lines_count):
    """生成数据文件"""
    with open(filename, 'w', encoding='utf-8') as file:
        for _ in range(lines_count):
            file.write(generate_data_line())

# 调用函数生成文件
generate_data_file('random_data.txt', 100000)