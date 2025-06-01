#!/bin/bash

# Script to create the initial project structure and files,
# AND to create a companion 'apply_update.sh' script for future modifications.

echo "Creating Threads Clone project structure and initial files..."
echo "This script will create a directory named 'threads_clone' in the current location."
read -p "Proceed? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Operation cancelled."
    exit 0
fi

BASE_DIR="threads_clone"

if [ -d "$BASE_DIR" ]; then
    read -p "'$BASE_DIR' already exists. Overwrite its contents? (This is destructive if 'y') (y/N): " overwrite_confirm
    if [[ "$overwrite_confirm" != "y" && "$overwrite_confirm" != "Y" ]]; then
        echo "Operation cancelled. '$BASE_DIR' was not modified."
        exit 0
    fi
    echo "Removing existing '$BASE_DIR' and recreating..."
    rm -rf "$BASE_DIR" # Remove existing to ensure clean slate
fi
mkdir -p "$BASE_DIR"


# Change to the project's parent directory to correctly create apply_update.sh alongside threads_clone
# but all project files will be created inside BASE_DIR.
# This script itself should be run from where you want 'threads_clone' and 'apply_update.sh' to appear.

# --- Create Backend Structure ---
echo "Creating backend structure inside $BASE_DIR..."
mkdir -p "$BASE_DIR/backend/app"
mkdir -p "$BASE_DIR/backend/migrations"
mkdir -p "$BASE_DIR/backend/instance"

# --- Create Backend Files ---

# backend/.env (Instructions for user)
cat << 'EOF' > "$BASE_DIR/backend/.env_INSTRUCTIONS.txt"
---------------------------------------------------------------------
IMPORTANT: Create a file named '.env' in the 'threads_clone/backend/' directory.
Populate 'backend/.env' with the following content, replacing placeholder values:

SECRET_KEY='your_super_secret_flask_key_please_change_me'
API_KEY='your_super_secret_api_key_for_public_endpoints_change_me'
# SQLALCHEMY_DATABASE_URI='sqlite:///instance/threads.db' # Default
# Example for PostgreSQL:
# SQLALCHEMY_DATABASE_URI='postgresql://youruser:yourpassword@localhost:5432/threads_db_name'
---------------------------------------------------------------------
EOF
echo "Created instructions for backend/.env in $BASE_DIR/backend/.env_INSTRUCTIONS.txt"


# backend/requirements.txt
cat << 'EOF' > "$BASE_DIR/backend/requirements.txt"
Flask
Flask-SQLAlchemy
Flask-Migrate
Flask-Cors
Werkzeug
python-dotenv
SQLAlchemy
EOF
echo "Created $BASE_DIR/backend/requirements.txt"

# backend/config.py
cat << 'EOF' > "$BASE_DIR/backend/config.py"
import os
from dotenv import load_dotenv

# This assumes config.py is in backend/
# So, .env should also be in backend/
basedir = os.path.abspath(os.path.dirname(__file__))
dotenv_path = os.path.join(basedir, '.env')

if os.path.exists(dotenv_path):
    load_dotenv(dotenv_path)
else:
    print(f"Warning: .env file not found at {dotenv_path}. Using default configurations or environment variables if set globally.")


class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY') or 'a_very_default_unsafe_secret_key_pls_change'
    
    instance_folder_path = os.path.join(os.path.dirname(__file__), 'instance')
    SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL') or \
        'sqlite:///' + os.path.join(instance_folder_path, 'threads.db')
    
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    API_KEY = os.environ.get('API_KEY') or 'default_api_key_shhh_change_me_also'

if not os.path.exists(Config.instance_folder_path):
    try:
        os.makedirs(Config.instance_folder_path)
        print(f"Created instance directory: {Config.instance_folder_path}")
    except OSError as e:
        print(f"Error creating instance directory {Config.instance_folder_path}: {e}")
EOF
echo "Created $BASE_DIR/backend/config.py"

# backend/run.py
cat << 'EOF' > "$BASE_DIR/backend/run.py"
from app import create_app

app = create_app()

if __name__ == '__main__':
    app.run(host='0.0.0.0', debug=True, port=5001)
EOF
chmod +x "$BASE_DIR/backend/run.py"
echo "Created $BASE_DIR/backend/run.py"


# backend/app/__init__.py
cat << 'EOF' > "$BASE_DIR/backend/app/__init__.py"
import os
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_cors import CORS
from config import Config 


db = SQLAlchemy()
migrate = Migrate()

def create_app(config_class=Config):
    project_backend_root = os.path.dirname(os.path.abspath(__file__)) 
    project_backend_root = os.path.dirname(project_backend_root)      
    
    app = Flask(__name__, instance_path=os.path.join(project_backend_root, 'instance'), instance_relative_config=True)
    app.config.from_object(config_class)

    db.init_app(app)
    migrate.init_app(app, db)
    CORS(app) 

    from app.models import User, Post, Like 
    from app.routes import bp as main_bp
    app.register_blueprint(main_bp)

    with app.app_context():
        db.create_all() 
    return app
EOF
echo "Created $BASE_DIR/backend/app/__init__.py"

# backend/app/models.py
cat << 'EOF' > "$BASE_DIR/backend/app/models.py"
from datetime import datetime, timezone
from werkzeug.security import generate_password_hash, check_password_hash
from app import db
from sqlalchemy.ext.hybrid import hybrid_property

followers = db.Table('followers',
    db.Column('follower_id', db.Integer, db.ForeignKey('user.id'), primary_key=True),
    db.Column('followed_id', db.Integer, db.ForeignKey('user.id'), primary_key=True)
)

class User(db.Model):
    __tablename__ = 'user'
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(64), index=True, unique=True, nullable=False)
    email = db.Column(db.String(120), index=True, unique=True, nullable=False)
    password_hash = db.Column(db.String(256))
    bio = db.Column(db.String(280))
    profile_picture = db.Column(db.String(200)) 
    created_at = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))

    posts = db.relationship('Post', backref='author', lazy='dynamic', cascade="all, delete-orphan")
    likes_given = db.relationship('Like', foreign_keys='Like.user_id', backref='user', lazy='dynamic', cascade="all, delete-orphan")

    followed = db.relationship(
        'User', secondary=followers,
        primaryjoin=(followers.c.follower_id == id),
        secondaryjoin=(followers.c.followed_id == id),
        backref=db.backref('user_followers', lazy='dynamic'), 
        lazy='dynamic')

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        if self.password_hash is None: 
            return False
        return check_password_hash(self.password_hash, password)

    def follow(self, user_to_follow):
        if not self.is_following(user_to_follow):
            self.followed.append(user_to_follow)

    def unfollow(self, user_to_unfollow):
        if self.is_following(user_to_unfollow):
            self.followed.remove(user_to_unfollow)

    def is_following(self, user_to_check):
        return self.followed.filter(
            followers.c.followed_id == user_to_check.id).count() > 0

    @hybrid_property
    def posts_count(self):
        return self.posts.count()
    
    @hybrid_property
    def followers_count(self):
        return self.user_followers.count()

    @hybrid_property
    def following_count(self):
        return self.followed.count()

    def to_dict(self, include_email=False, current_user_obj=None):
        data = {
            'id': self.id,
            'username': self.username,
            'bio': self.bio,
            'profile_picture': self.profile_picture,
            'created_at': self.created_at.isoformat() + 'Z' if self.created_at else None,
            'followers_count': self.followers_count,
            'following_count': self.following_count,
            'posts_count': self.posts_count
        }
        if include_email: 
            data['email'] = self.email
        
        if current_user_obj and current_user_obj.id != self.id:
            data['is_followed_by_current_user'] = current_user_obj.is_following(self)
        elif current_user_obj and current_user_obj.id == self.id:
            data['is_followed_by_current_user'] = False 
        
        return data

class Post(db.Model):
    __tablename__ = 'post'
    id = db.Column(db.Integer, primary_key=True)
    body = db.Column(db.String(500), nullable=False)
    timestamp = db.Column(db.DateTime, index=True, default=lambda: datetime.now(timezone.utc))
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False) 
    parent_id = db.Column(db.Integer, db.ForeignKey('post.id'), nullable=True)

    likes_received = db.relationship('Like', foreign_keys='Like.post_id', backref='post', lazy='dynamic', cascade="all, delete-orphan")
    replies = db.relationship('Post', backref=db.backref('parent', remote_side=[id]), lazy='dynamic', cascade="all, delete-orphan")

    @hybrid_property
    def likes_count(self):
        return self.likes_received.count()

    @hybrid_property
    def replies_count(self):
        return self.replies.count()

    def to_dict(self, current_user_obj=None):
        data = {
            'id': self.id,
            'body': self.body,
            'timestamp': self.timestamp.isoformat() + 'Z' if self.timestamp else None,
            'user_id': self.user_id,
            'author_username': self.author.username, 
            'author_profile_pic': self.author.profile_picture, 
            'parent_id': self.parent_id,
            'likes_count': self.likes_count,
            'replies_count': self.replies_count,
            'is_liked_by_current_user': False
        }
        if current_user_obj:
            data['is_liked_by_current_user'] = self.likes_received.filter_by(user_id=current_user_obj.id).count() > 0
        return data

class Like(db.Model):
    __tablename__ = 'like'
    id = db.Column(db.Integer, primary_key=True) 
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False) 
    post_id = db.Column(db.Integer, db.ForeignKey('post.id'), nullable=False) 
    timestamp = db.Column(db.DateTime, default=lambda: datetime.now(timezone.utc))

    __table_args__ = (db.UniqueConstraint('user_id', 'post_id', name='_user_post_uc'),)
EOF
echo "Created $BASE_DIR/backend/app/models.py"

# backend/app/auth.py
cat << 'EOF' > "$BASE_DIR/backend/app/auth.py"
from functools import wraps
from flask import request, jsonify, g, current_app
from app.models import User

def protected_route(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        auth_header = request.headers.get('Authorization')
        user_id_from_token = None
        g.current_user = None 
        g.is_api_key_auth = False

        if auth_header:
            parts = auth_header.split()
            if len(parts) == 2:
                auth_type, token = parts
                if auth_type.lower() == 'bearer':
                    try:
                        user_id_from_token = int(token)
                        g.current_user = User.query.get(user_id_from_token)
                        if not g.current_user:
                            current_app.logger.warning(f"Bearer token for non-existent user ID: {user_id_from_token}")
                    except ValueError:
                        current_app.logger.warning(f"Invalid Bearer token format (not an int): {token}")
                elif auth_type.lower() == 'apikey' and token == current_app.config['API_KEY']:
                    g.is_api_key_auth = True
                else:
                    current_app.logger.warning(f"Invalid token type: {auth_type} or mismatched API key.")
            else:
                current_app.logger.warning(f"Malformed Authorization header: {auth_header}")
        
        return f(*args, **kwargs)
    return decorated_function

def require_login(f):
    @wraps(f)
    @protected_route 
    def decorated_function(*args, **kwargs):
        if not g.current_user:
            return jsonify({'message': 'Login required for this action'}), 401
        return f(*args, **kwargs)
    return decorated_function

def basic_login(username, password):
    user = User.query.filter(User.username.ilike(username)).first()
    if user and user.check_password(password):
        return user
    return None
EOF
echo "Created $BASE_DIR/backend/app/auth.py"

# backend/app/routes.py
cat << 'EOF' > "$BASE_DIR/backend/app/routes.py"
from flask import Blueprint, request, jsonify, g, current_app
from app import db
from app.models import User, Post, Like
from app.auth import protected_route, require_login, basic_login
from sqlalchemy.exc import IntegrityError
from sqlalchemy import or_ 

bp = Blueprint('main', __name__, url_prefix='/api')

@bp.route('/register', methods=['POST'])
def register():
    data = request.get_json() or {}
    username = data.get('username')
    email = data.get('email')
    password = data.get('password')

    if not all([username, email, password]):
        return jsonify({'message': 'Missing username, email, or password'}), 400
    if not (3 <= len(username) <= 64):
        return jsonify({'message': 'Username must be between 3 and 64 characters'}), 400
    if not (6 <= len(password)): 
        return jsonify({'message': 'Password must be at least 6 characters long'}), 400
    if '@' not in email or '.' not in email.split('@')[-1]:
        return jsonify({'message': 'Invalid email format'}), 400

    if User.query.filter(User.username.ilike(username)).first(): 
        return jsonify({'message': 'Username already taken'}), 409
    if User.query.filter(User.email.ilike(email)).first(): 
        return jsonify({'message': 'Email already registered'}), 409

    user = User(username=username, email=email)
    user.set_password(password)
    db.session.add(user)
    try:
        db.session.commit()
        return jsonify({
            'message': 'User registered successfully',
            'token': str(user.id),
            'user': user.to_dict(include_email=True, current_user_obj=user) 
        }), 201
    except IntegrityError as e:
        db.session.rollback()
        current_app.logger.error(f"IntegrityError during registration: {e}")
        return jsonify({'message': 'Database error: Username or email might already exist despite checks.'}), 500
    except Exception as e:
        db.session.rollback()
        current_app.logger.error(f"General error during registration: {e}")
        return jsonify({'message': f'An unexpected error occurred: {str(e)}'}), 500

@bp.route('/login', methods=['POST'])
def login():
    data = request.get_json() or {}
    username = data.get('username')
    password = data.get('password')

    if not username or not password:
        return jsonify({'message': 'Missing username or password'}), 400

    user = basic_login(username, password) 
    if user:
        return jsonify({
            'message': 'Login successful',
            'token': str(user.id),
            'user': user.to_dict(include_email=True, current_user_obj=user)
        }), 200
    return jsonify({'message': 'Invalid username or password'}), 401

@bp.route('/me', methods=['GET'])
@require_login
def get_me():
    return jsonify(g.current_user.to_dict(include_email=True, current_user_obj=g.current_user)), 200

@bp.route('/users/search', methods=['GET'])
@protected_route 
def search_users():
    query = request.args.get('q', '').strip()
    if not query or len(query) < 1:
        return jsonify([]), 200

    search_term = f"%{query}%"
    users = User.query.filter(User.username.ilike(search_term)).limit(10).all()
    return jsonify([user.to_dict(current_user_obj=g.current_user) for user in users]), 200

@bp.route('/users/<username>', methods=['GET'])
@protected_route 
def get_user_profile(username):
    user = User.query.filter(User.username.ilike(username)).first_or_404(
        description=f"User '{username}' not found"
    )
    return jsonify(user.to_dict(current_user_obj=g.current_user)), 200

@bp.route('/users/<username>/posts', methods=['GET'])
@protected_route 
def get_user_posts(username):
    user = User.query.filter(User.username.ilike(username)).first_or_404(
        description=f"User '{username}' not found"
    )
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 10, type=int)

    posts_query = Post.query.filter_by(author=user, parent_id=None).order_by(Post.timestamp.desc())
    posts_paginated = posts_query.paginate(page=page, per_page=per_page, error_out=False)
    
    posts_data = [post.to_dict(current_user_obj=g.current_user) for post in posts_paginated.items]

    return jsonify({
        'posts': posts_data,
        'total_posts': posts_paginated.total,
        'current_page': posts_paginated.page,
        'total_pages': posts_paginated.pages
    }), 200

@bp.route('/users/<int:user_id_to_action>/follow', methods=['POST'])
@require_login
def follow_user_route(user_id_to_action):
    user_to_follow = User.query.get_or_404(user_id_to_action)
    if g.current_user.id == user_to_follow.id:
        return jsonify({'message': "You cannot follow yourself"}), 400
    if g.current_user.is_following(user_to_follow):
        return jsonify({'message': f"You are already following {user_to_follow.username}"}), 400

    g.current_user.follow(user_to_follow)
    db.session.commit()
    return jsonify({'message': f"You are now following {user_to_follow.username}", 'is_following': True}), 200

@bp.route('/users/<int:user_id_to_action>/unfollow', methods=['POST'])
@require_login
def unfollow_user_route(user_id_to_action):
    user_to_unfollow = User.query.get_or_404(user_id_to_action)
    if g.current_user.id == user_to_unfollow.id: 
        return jsonify({'message': "Action not applicable to self"}), 400
    if not g.current_user.is_following(user_to_unfollow):
        return jsonify({'message': f"You are not following {user_to_unfollow.username}"}), 400

    g.current_user.unfollow(user_to_unfollow)
    db.session.commit()
    return jsonify({'message': f"You have unfollowed {user_to_unfollow.username}", 'is_following': False}), 200

@bp.route('/users/<username>/followers', methods=['GET'])
@protected_route
def get_user_followers_route(username):
    user = User.query.filter(User.username.ilike(username)).first_or_404()
    followers_list = [u.to_dict(current_user_obj=g.current_user) for u in user.user_followers.all()]
    return jsonify(followers_list), 200

@bp.route('/users/<username>/following', methods=['GET'])
@protected_route
def get_user_following_route(username):
    user = User.query.filter(User.username.ilike(username)).first_or_404()
    followed_list = [u.to_dict(current_user_obj=g.current_user) for u in user.followed.all()]
    return jsonify(followed_list), 200

@bp.route('/posts', methods=['POST'])
@require_login
def create_post():
    data = request.get_json() or {}
    body = data.get('body')
    parent_id_str = data.get('parent_id') 
    parent_id = None
    if parent_id_str:
        try:
            parent_id = int(parent_id_str)
        except ValueError:
            return jsonify({'message': 'Invalid parent_id format.'}), 400

    if not body or len(body.strip()) == 0:
        return jsonify({'message': 'Post body cannot be empty'}), 400
    if len(body) > 500: 
        return jsonify({'message': 'Post body cannot exceed 500 characters'}), 400
    
    if parent_id:
        parent_post = Post.query.get(parent_id)
        if not parent_post:
            return jsonify({'message': 'Parent post not found'}), 404

    post = Post(body=body.strip(), author=g.current_user, parent_id=parent_id)
    db.session.add(post)
    db.session.commit()
    return jsonify(post.to_dict(current_user_obj=g.current_user)), 201

@bp.route('/posts', methods=['GET'])
@protected_route
def get_posts_feed():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 10, type=int)
    
    feed_query = None
    if g.current_user:
        followed_ids = [user.id for user in g.current_user.followed.all()]
        user_ids_for_feed = followed_ids + [g.current_user.id]
        feed_query = Post.query.filter(Post.user_id.in_(user_ids_for_feed), Post.parent_id.is_(None)).order_by(Post.timestamp.desc())
    elif g.is_api_key_auth:
        feed_query = Post.query.filter(Post.parent_id.is_(None)).order_by(Post.timestamp.desc())
    else: 
        if request.accept_mimetypes.accept_json and not request.accept_mimetypes.accept_html:
             return jsonify({'message': 'Authentication required for feed'}), 401
        else: 
             return "Authentication required for feed", 401

    posts_paginated = feed_query.paginate(page=page, per_page=per_page, error_out=False)
    posts_data = [post.to_dict(current_user_obj=g.current_user) for post in posts_paginated.items]

    return jsonify({
        'posts': posts_data,
        'total_posts': posts_paginated.total,
        'current_page': posts_paginated.page,
        'total_pages': posts_paginated.pages
    }), 200

@bp.route('/posts/<int:post_id>', methods=['GET'])
@protected_route
def get_post_details(post_id):
    post = Post.query.get_or_404(post_id)
    post_data = post.to_dict(current_user_obj=g.current_user)
    replies_data = [reply.to_dict(current_user_obj=g.current_user) 
                    for reply in post.replies.order_by(Post.timestamp.asc()).all()]
    post_data['replies'] = replies_data
    return jsonify(post_data), 200

@bp.route('/posts/<int:post_id>/like', methods=['POST'])
@require_login
def like_post_route(post_id): 
    post_to_like = Post.query.get_or_404(post_id) 
    like_instance = Like.query.filter_by(user_id=g.current_user.id, post_id=post_to_like.id).first()

    if like_instance:
        db.session.delete(like_instance)
        action_message = 'Post unliked'
        liked_status = False
    else:
        new_like = Like(user_id=g.current_user.id, post_id=post_to_like.id) 
        db.session.add(new_like)
        action_message = 'Post liked'
        liked_status = True
    
    db.session.commit()
    updated_post = Post.query.get(post_id) 
    return jsonify({
        'message': action_message,
        'liked': liked_status,
        'likes_count': updated_post.likes_count
    }), 200

@bp.route('/posts/<int:post_id>', methods=['DELETE'])
@require_login
def delete_post_route(post_id): 
    post_to_delete = Post.query.get_or_404(post_id) 
    if post_to_delete.user_id != g.current_user.id:
        return jsonify({'message': 'Permission denied. You are not the author of this post.'}), 403
    
    db.session.delete(post_to_delete)
    db.session.commit()
    return jsonify({'message': 'Post deleted successfully'}), 200
EOF
echo "Created $BASE_DIR/backend/app/routes.py"

# --- Create Frontend Structure ---
echo "Creating frontend structure inside $BASE_DIR..."
mkdir -p "$BASE_DIR/frontend/css"
mkdir -p "$BASE_DIR/frontend/js"

# --- Create Frontend Files ---
# frontend/index.html
cat << 'EOF' > "$BASE_DIR/frontend/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Threads Clone</title>
    <link rel="stylesheet" href="css/style.css">
</head>
<body>
    <header>
        <h1><a href="index.html" class="logo-link">Threads Clone</a></h1>
        <nav>
            <a href="index.html" class="nav-link">Home</a>
            <div class="search-container">
                <input type="search" id="search-bar" placeholder="Search users...">
                <div id="search-results-dropdown" class="search-results-dropdown" style="display:none;"></div>
            </div>
            <div id="auth-nav-links" class="auth-nav-links">
                <a href="login.html" class="nav-link">Login</a>
                <a href="register.html" class="nav-link">Register</a>
            </div>
            <div id="user-nav-actions" class="user-nav-actions" style="display:none;">
                <a href="#" id="my-profile-link" class="nav-link">Profile</a>
                <button id="logout-button" class="nav-button">Logout</button>
            </div>
        </nav>
    </header>

    <main>
        <section id="create-post-section" style="display:none;">
            <h2>Create New Post</h2>
            <textarea id="post-body-textarea" placeholder="What's happening? (Max 500 chars)" maxlength="500"></textarea>
            <div id="char-count" class="char-count">0/500</div>
            <button id="submit-post-button" class="button primary-button">Post</button>
        </section>

        <section id="feed-section">
            <h2>Feed</h2>
            <div id="posts-feed-container" class="posts-container">
                <p class="loading-text">Loading posts...</p>
            </div>
        </section>
    </main>

    <footer>
        <p>&copy; 2024 Threads Clone Project</p>
    </footer>

    <script src="js/api.js"></script>
    <script src="js/common.js"></script>
    <script src="js/app.js"></script>
</body>
</html>
EOF
echo "Created $BASE_DIR/frontend/index.html"

# frontend/login.html
cat << 'EOF' > "$BASE_DIR/frontend/login.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Login - Threads Clone</title>
    <link rel="stylesheet" href="css/style.css">
</head>
<body>
    <header>
        <h1><a href="index.html" class="logo-link">Threads Clone - Login</a></h1>
    </header>
    <main class="auth-page">
        <form id="login-form" class="auth-form">
            <h2>Login</h2>
            <div class="form-group">
                <label for="username">Username:</label>
                <input type="text" id="username" name="username" required>
            </div>
            <div class="form-group">
                <label for="password">Password:</label>
                <input type="password" id="password" name="password" required>
            </div>
            <button type="submit" class="button primary-button">Login</button>
            <p id="login-message" class="form-message" style="display:none;"></p>
        </form>
        <p class="auth-switch">Don't have an account? <a href="register.html">Register here</a></p>
    </main>
    <script src="js/api.js"></script>
    <script src="js/common.js"></script> 
    <script src="js/auth.js"></script>
</body>
</html>
EOF
echo "Created $BASE_DIR/frontend/login.html"

# frontend/register.html
cat << 'EOF' > "$BASE_DIR/frontend/register.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Register - Threads Clone</title>
    <link rel="stylesheet" href="css/style.css">
</head>
<body>
    <header>
        <h1><a href="index.html" class="logo-link">Threads Clone - Register</a></h1>
    </header>
    <main class="auth-page">
        <form id="register-form" class="auth-form">
            <h2>Register</h2>
            <div class="form-group">
                <label for="username">Username (3-64 chars):</label>
                <input type="text" id="username" name="username" required minlength="3" maxlength="64">
            </div>
            <div class="form-group">
                <label for="email">Email:</label>
                <input type="email" id="email" name="email" required>
            </div>
            <div class="form-group">
                <label for="password">Password (min 6 chars):</label>
                <input type="password" id="password" name="password" required minlength="6">
            </div>
            <button type="submit" class="button primary-button">Register</button>
            <p id="register-message" class="form-message" style="display:none;"></p>
        </form>
        <p class="auth-switch">Already have an account? <a href="login.html">Login here</a></p>
    </main>
    <script src="js/api.js"></script>
    <script src="js/common.js"></script> 
    <script src="js/auth.js"></script>
</body>
</html>
EOF
echo "Created $BASE_DIR/frontend/register.html"

# frontend/profile.html
cat << 'EOF' > "$BASE_DIR/frontend/profile.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>User Profile - Threads Clone</title>
    <link rel="stylesheet" href="css/style.css">
</head>
<body>
    <header>
        <h1><a href="index.html" class="logo-link">Threads Clone</a></h1>
         <nav>
            <a href="index.html" class="nav-link">Home</a>
            <div class="search-container">
                <input type="search" id="search-bar" placeholder="Search users...">
                <div id="search-results-dropdown" class="search-results-dropdown" style="display:none;"></div>
            </div>
            <div id="auth-nav-links" class="auth-nav-links">
                <a href="login.html" class="nav-link">Login</a>
                <a href="register.html" class="nav-link">Register</a>
            </div>
            <div id="user-nav-actions" class="user-nav-actions" style="display:none;">
                <a href="#" id="my-profile-link" class="nav-link">My Profile</a>
                <button id="logout-button" class="nav-button">Logout</button>
            </div>
        </nav>
    </header>

    <main>
        <section id="profile-details-section">
            <div id="profile-header-content" class="profile-header">
                <p class="loading-text">Loading profile...</p>
            </div>
            <div id="profile-action-buttons" class="profile-action-buttons">
                 <button id="follow-unfollow-profile-button" class="button" style="display:none;"></button>
            </div>
        </section>

        <section id="user-posts-section">
            <h2>Posts</h2>
            <div id="user-posts-container" class="posts-container">
                <p class="loading-text">Loading posts...</p>
            </div>
        </section>
    </main>

    <footer>
        <p>&copy; 2024 Threads Clone Project</p>
    </footer>

    <script src="js/api.js"></script>
    <script src="js/common.js"></script>
    <script src="js/profile.js"></script>
</body>
</html>
EOF
echo "Created $BASE_DIR/frontend/profile.html"

# frontend/css/style.css
cat << 'EOF' > "$BASE_DIR/frontend/css/style.css"
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;margin:0;padding:0;background-color:#f0f2f5;color:#1c1e21;line-height:1.5;font-size:16px}a{color:#007bff;text-decoration:none}a:hover{text-decoration:underline}header{background-color:#fff;padding:10px 15px;border-bottom:1px solid #dddfe2;display:flex;justify-content:space-between;align-items:center;position:sticky;top:0;z-index:1000}header .logo-link{font-size:1.25em;font-weight:700;color:#1c1e21;text-decoration:none}header nav{display:flex;align-items:center;gap:10px}header .nav-link,header .nav-button{font-size:.9em;padding:6px 10px;border-radius:4px;color:#007bff}header .nav-button{background-color:transparent;border:1px solid #007bff;cursor:pointer}header .nav-button:hover{background-color:#007bff;color:#fff}.search-container{position:relative;display:flex;align-items:center}#search-bar{padding:6px 10px;border:1px solid #ccd0d5;border-radius:15px;font-size:.9em;min-width:150px}.search-results-dropdown{position:absolute;top:calc(100% + 5px);left:0;width:100%;min-width:200px;background:#fff;border:1px solid #dddfe2;border-radius:4px;box-shadow:0 4px 8px rgba(0,0,0,.1);z-index:1001;max-height:300px;overflow-y:auto}.search-results-dropdown div{padding:8px 12px;cursor:pointer;font-size:.9em;border-bottom:1px solid #f0f2f5;display:flex;align-items:center}.search-results-dropdown div:last-child{border-bottom:none}.search-results-dropdown div:hover{background-color:#f0f2f5}main{max-width:600px;margin:15px auto;padding:15px;background-color:#fff}main.auth-page{max-width:400px;margin-top:50px;padding:20px;background-color:#fff;border-radius:8px;box-shadow:0 2px 10px rgba(0,0,0,.1)}.auth-form{display:flex;flex-direction:column;gap:15px}.auth-form h2{text-align:center;margin-bottom:10px;font-weight:500;color:#1c1e21}.form-group{display:flex;flex-direction:column}.form-group label{margin-bottom:5px;font-size:.9em;color:#606770}.form-group input[type=text],.form-group input[type=email],.form-group input[type=password]{padding:10px;border:1px solid #ccd0d5;border-radius:6px;font-size:1em}.form-message{margin-top:10px;font-size:.9em;text-align:center;padding:8px;border-radius:4px}.form-message.error{color:#721c24;background-color:#f8d7da;border:1px solid #f5c6cb}.form-message.success{color:#155724;background-color:#d4edda;border:1px solid #c3e6cb}.auth-switch{text-align:center;margin-top:20px;font-size:.9em}.button{padding:10px 15px;border:none;border-radius:6px;cursor:pointer;font-size:1em;font-weight:500;text-align:center;transition:background-color .2s ease-in-out}.primary-button{background-color:#007bff;color:#fff}.primary-button:hover{background-color:#0056b3}.primary-button:disabled{background-color:#a0c7e8;cursor:not-allowed}.secondary-button{background-color:#6c757d;color:#fff}.secondary-button:hover{background-color:#545b62}.action-button{background-color:transparent;border:1px solid #ccd0d5;color:#606770;padding:6px 10px;font-size:.85em;border-radius:15px}.action-button:hover{background-color:#f0f2f5}.action-button.liked{background-color:#ffe0e6;border-color:#ffb3c1;color:#c90035}#create-post-section{margin-bottom:20px;padding:15px;border:1px solid #dddfe2;border-radius:8px}#create-post-section h2{margin-top:0;font-size:1.1em;font-weight:500}#post-body-textarea{width:calc(100% - 22px);min-height:80px;margin-bottom:5px;padding:10px;border:1px solid #ccd0d5;border-radius:6px;font-size:1em;resize:vertical}.char-count{font-size:.8em;color:#606770;text-align:right;margin-bottom:10px}.posts-container{margin-top:10px}.post{padding:15px 0;border-bottom:1px solid #eee}.post:last-child{border-bottom:none}.post-header{display:flex;align-items:center;margin-bottom:8px}.post-author-avatar{width:40px;height:40px;border-radius:50%;margin-right:10px;background-color:#e0e0e0;object-fit:cover;border:1px solid #ccc}.post-author-info .author-username{font-weight:600;color:#1c1e21}.post-author-info .post-timestamp{font-size:.8em;color:#606770}.delete-post-btn{background:0 0;border:none;color:#606770;font-size:1.2em;cursor:pointer;margin-left:auto;padding:5px}.delete-post-btn:hover{color:#dc3545}.post-body{margin:5px 0 10px;word-wrap:break-word;white-space:pre-wrap;font-size:.95em}.post-actions{display:flex;gap:10px;margin-top:10px}.profile-header{padding-bottom:15px;margin-bottom:15px;border-bottom:1px solid #eee;text-align:center}.profile-avatar{width:100px;height:100px;border-radius:50%;margin:0 auto 10px;background-color:#e0e0e0;object-fit:cover;border:2px solid #fff;box-shadow:0 1px 3px rgba(0,0,0,.2)}.profile-header h2{margin:5px 0;font-size:1.5em}.profile-header .profile-bio{margin:5px 0 10px;color:#606770;font-size:.95em}.profile-stats{display:flex;justify-content:center;gap:20px;font-size:.9em;margin-top:10px}.profile-stats span strong{display:block;font-size:1.1em;color:#1c1e21}.profile-stats span{color:#606770}.profile-action-buttons{text-align:center;margin-bottom:20px}#follow-unfollow-profile-button{padding:8px 20px}#follow-unfollow-profile-button.following{background-color:#6c757d;color:#fff}#follow-unfollow-profile-button.following:hover{background-color:#545b62}.loading-text{text-align:center;color:#606770;padding:20px;font-style:italic}.error-text{color:#dc3545;font-weight:500;text-align:center;padding:10px}.error-text a{color:#a71d2a;text-decoration:underline}footer{text-align:center;padding:20px;font-size:.9em;color:#606770;border-top:1px solid #eee;margin-top:20px}@media (max-width:768px){header{padding:10px}header .logo-link{font-size:1.1em}header nav{gap:5px}header .nav-link,header .nav-button{font-size:.85em;padding:5px 8px}#search-bar{min-width:100px;max-width:120px;font-size:.85em}main{margin:10px auto;padding:10px}main.auth-page{margin-top:20px;box-shadow:none;border-radius:0}.button{font-size:.95em}#create-post-section textarea{min-height:60px}}@media (max-width:480px){body{font-size:15px}.search-container{flex-grow:1}#search-bar{max-width:none}.profile-avatar{width:80px;height:80px}.profile-header h2{font-size:1.3em}.post-author-avatar{width:35px;height:35px}}
EOF
echo "Created $BASE_DIR/frontend/css/style.css"

# frontend/js/api.js
cat << 'EOF' > "$BASE_DIR/frontend/js/api.js"
const API_BASE_URL = 'http://localhost:5001/api'; 

async function request(endpoint, method = 'GET', data = null) {
    const headers = { 'Content-Type': 'application/json' };
    if (window.AppState && AppState.currentToken) {
        headers['Authorization'] = `Bearer ${AppState.currentToken}`;
    }

    const config = {
        method: method,
        headers: headers,
    };

    if (data && (method === 'POST' || method === 'PUT' || method === 'PATCH' || method === 'DELETE')) {
        config.body = JSON.stringify(data);
    }

    try {
        const response = await fetch(`${API_BASE_URL}${endpoint}`, config);
        
        if (response.status === 204) { 
            return Promise.resolve({}); 
        }

        const responseData = await response.json();

        if (!response.ok) {
            console.error('API Error:', response.status, responseData.message || response.statusText, `Endpoint: ${method} ${endpoint}`);
            const error = new Error(responseData.message || response.statusText || `HTTP error! status: ${response.status}`);
            error.status = response.status;
            error.data = responseData; 
            return Promise.reject(error);
        }
        return responseData;
    } catch (error) {
        console.error('Network or parsing error:', error, `Endpoint: ${method} ${endpoint}`);
        const customError = new Error(error.message || 'Network error or invalid JSON response. Is the backend server running?');
        customError.status = 0; 
        return Promise.reject(customError);
    }
}
EOF
echo "Created $BASE_DIR/frontend/js/api.js"

# frontend/js/common.js
cat << 'EOF' > "$BASE_DIR/frontend/js/common.js"
const AppState = {
    currentUser: JSON.parse(localStorage.getItem('threadsUser')),
    currentToken: localStorage.getItem('threadsToken')
};

function updateGlobalAuthState() {
    AppState.currentUser = JSON.parse(localStorage.getItem('threadsUser'));
    AppState.currentToken = localStorage.getItem('threadsToken');
}

function updateCommonNavUI() {
    updateGlobalAuthState(); 

    const authNavLinks = document.getElementById('auth-nav-links');
    const userNavActions = document.getElementById('user-nav-actions');
    const myProfileLink = document.getElementById('my-profile-link');
    const logoutButton = document.getElementById('logout-button');
    const createPostSection = document.getElementById('create-post-section');


    if (AppState.currentToken && AppState.currentUser) {
        if (authNavLinks) authNavLinks.style.display = 'none';
        if (userNavActions) userNavActions.style.display = 'flex'; 
        if (myProfileLink) {
            myProfileLink.textContent = AppState.currentUser.username;
            myProfileLink.href = `profile.html?username=${encodeURIComponent(AppState.currentUser.username)}`;
        }
        if (createPostSection && (window.location.pathname.endsWith('index.html') || window.location.pathname === '/')) {
             createPostSection.style.display = 'block';
        }
    } else {
        if (authNavLinks) authNavLinks.style.display = 'flex';
        if (userNavActions) userNavActions.style.display = 'none';
        if (createPostSection) createPostSection.style.display = 'none';
    }

    if (logoutButton) {
        logoutButton.onclick = () => { 
            localStorage.removeItem('threadsToken');
            localStorage.removeItem('threadsUser');
            updateGlobalAuthState(); 
            updateCommonNavUI();    
            
            if (window.location.pathname.includes('index.html') || window.location.pathname === '/') {
                if (typeof loadFeedPosts === 'function') { 
                    loadFeedPosts(); 
                } else {
                     window.location.reload(); 
                }
            } else {
                window.location.href = 'login.html'; 
            }
        };
    }
}

let searchDebounceTimeout;
async function handleGlobalSearch(event, searchResultsContainerEl) {
    const query = event.target.value.trim();
    if (!searchResultsContainerEl) return;

    if (query.length < 1) {
        searchResultsContainerEl.style.display = 'none';
        searchResultsContainerEl.innerHTML = '';
        return;
    }

    clearTimeout(searchDebounceTimeout);
    searchDebounceTimeout = setTimeout(async () => {
        try {
            const results = await request(`/users/search?q=${encodeURIComponent(query)}`); 
            renderGlobalSearchResults(results, searchResultsContainerEl);
        } catch (error) {
            console.error("Search error:", error);
            searchResultsContainerEl.innerHTML = `<div class="error-text" style="padding: 8px 12px;">Error searching</div>`;
            searchResultsContainerEl.style.display = 'block';
        }
    }, 300);
}

function renderGlobalSearchResults(users, searchResultsContainerEl) {
    if (!searchResultsContainerEl) return;
    searchResultsContainerEl.innerHTML = '';
    if (users.length === 0) {
        searchResultsContainerEl.innerHTML = '<div>No users found</div>';
    } else {
        users.forEach(user => {
            const userDiv = document.createElement('div');
            const userImg = document.createElement('img');
            userImg.src = escapeHTML(user.profile_picture) || 'https://via.placeholder.com/30?text=U';
            userImg.alt = escapeHTML(user.username);
            userImg.style.width = '30px';
            userImg.style.height = '30px';
            userImg.style.borderRadius = '50%';
            userImg.style.marginRight = '8px';
            userImg.style.verticalAlign = 'middle';

            const userNameSpan = document.createElement('span');
            userNameSpan.textContent = escapeHTML(user.username);

            userDiv.appendChild(userImg);
            userDiv.appendChild(userNameSpan);
            
            userDiv.onclick = () => {
                window.location.href = `profile.html?username=${encodeURIComponent(user.username)}`;
                searchResultsContainerEl.style.display = 'none';
            };
            searchResultsContainerEl.appendChild(userDiv);
        });
    }
    searchResultsContainerEl.style.display = 'block';
}

function initializeCommonUI() {
    updateCommonNavUI(); 

    const searchBar = document.getElementById('search-bar');
    const searchResultsDropdown = document.getElementById('search-results-dropdown');

    if (searchBar && searchResultsDropdown) {
        searchBar.addEventListener('input', (event) => handleGlobalSearch(event, searchResultsDropdown));
        searchBar.addEventListener('focus', () => {
            if(searchResultsDropdown.children.length > 0 && searchResultsDropdown.textContent.trim() !== '') { 
                searchResultsDropdown.style.display = 'block';
            }
        });
        document.addEventListener('click', (event) => { 
            if (searchResultsDropdown && !searchBar.contains(event.target) && !searchResultsDropdown.contains(event.target)) {
                searchResultsDropdown.style.display = 'none';
            }
        });
    }
}

function displayMessage(element, message, type = 'info') {
    if (!element) return;
    element.textContent = message;
    element.className = 'form-message'; 
    if (type === 'error') {
        element.classList.add('error');
    } else if (type === 'success') {
        element.classList.add('success');
    }
    element.style.display = 'block'; 
}

function formatTimestamp(isoString) {
    if (!isoString) return 'Date unknown';
    try {
        const date = new Date(isoString);
        if (isNaN(date.getTime())) return 'Invalid date'; 
        return date.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' });
    } catch (e) {
        console.error("Error formatting timestamp:", isoString, e);
        return 'Date error';
    }
}

function escapeHTML(str) {
    if (str === null || str === undefined) return '';
    return String(str)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#039;");
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeCommonUI);
} else {
    initializeCommonUI(); 
}
EOF
echo "Created $BASE_DIR/frontend/js/common.js"

# frontend/js/auth.js
cat << 'EOF' > "$BASE_DIR/frontend/js/auth.js"
document.addEventListener('DOMContentLoaded', () => {
    const loginForm = document.getElementById('login-form');
    const registerForm = document.getElementById('register-form');
    const loginMessageEl = document.getElementById('login-message');
    const registerMessageEl = document.getElementById('register-message');

    if (loginForm) {
        loginForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            if(loginMessageEl) loginMessageEl.style.display = 'none'; 
            const username = loginForm.username.value;
            const password = loginForm.password.value;
            try {
                const data = await request('/login', 'POST', { username, password });
                localStorage.setItem('threadsToken', data.token);
                localStorage.setItem('threadsUser', JSON.stringify(data.user));
                updateGlobalAuthState(); 
                displayMessage(loginMessageEl, 'Login successful! Redirecting...', 'success');
                setTimeout(() => window.location.href = 'index.html', 1000); 
            } catch (error) {
                displayMessage(loginMessageEl, `Login failed: ${error.message || 'Unknown error'}`, 'error');
                console.error('Login error:', error);
            }
        });
    }

    if (registerForm) {
        registerForm.addEventListener('submit', async (e) => {
            e.preventDefault();
            if(registerMessageEl) registerMessageEl.style.display = 'none'; 
            const username = registerForm.username.value;
            const email = registerForm.email.value;
            const password = registerForm.password.value;

            if (password.length < 6) {
                 displayMessage(registerMessageEl, 'Password must be at least 6 characters long.', 'error');
                 return;
            }
            if (username.length < 3 || username.length > 64) {
                displayMessage(registerMessageEl, 'Username must be between 3 and 64 characters.', 'error');
                return;
            }
            if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
                displayMessage(registerMessageEl, 'Please enter a valid email address.', 'error');
                return;
            }

            try {
                const data = await request('/register', 'POST', { username, email, password });
                localStorage.setItem('threadsToken', data.token);
                localStorage.setItem('threadsUser', JSON.stringify(data.user));
                updateGlobalAuthState(); 
                displayMessage(registerMessageEl, 'Registration successful! Redirecting...', 'success');
                setTimeout(() => window.location.href = 'index.html', 1000);
            } catch (error) {
                displayMessage(registerMessageEl, `Registration failed: ${error.message || 'Unknown error'}`, 'error');
                console.error('Registration error:', error);
            }
        });
    }
});
EOF
echo "Created $BASE_DIR/frontend/js/auth.js"

# frontend/js/app.js
cat << 'EOF' > "$BASE_DIR/frontend/js/app.js"
document.addEventListener('DOMContentLoaded', () => {
    const postsContainer = document.getElementById('posts-feed-container');
    const postBodyTextarea = document.getElementById('post-body-textarea');
    const submitPostButton = document.getElementById('submit-post-button');
    const charCountDisplay = document.getElementById('char-count');

    const MAX_CHARS = 500;

    if (postBodyTextarea && charCountDisplay) {
        postBodyTextarea.addEventListener('input', () => {
            const currentLength = postBodyTextarea.value.length;
            charCountDisplay.textContent = `${currentLength}/${MAX_CHARS}`;
            if (currentLength > MAX_CHARS) {
                charCountDisplay.style.color = 'red';
                if (submitPostButton) submitPostButton.disabled = true;
            } else {
                charCountDisplay.style.color = '#606770';
                if (submitPostButton) submitPostButton.disabled = false;
            }
        });
    }

    async function loadFeedPostsGlobally() { 
        if (!postsContainer) return;
        postsContainer.innerHTML = '<p class="loading-text">Loading posts...</p>';
        try {
            const data = await request('/posts'); 
            renderPostsToContainer(data.posts, postsContainer);
        } catch (error) {
            console.error('Error loading feed posts:', error);
            let errorMessage = `Error loading posts: ${error.message || 'Could not fetch posts.'}`;
            if (error.status === 401 && !AppState.currentToken) {
                 errorMessage = `Please <a href="login.html">login</a> to view the feed.`;
            }
            postsContainer.innerHTML = `<p class="error-text">${errorMessage}</p>`; 
        }
    }
    window.loadFeedPosts = loadFeedPostsGlobally;


    function renderPostsToContainer(posts, containerEl) {
        if (!containerEl) return;
        containerEl.innerHTML = ''; 
        if (!posts || posts.length === 0) {
            containerEl.innerHTML = AppState.currentToken ? 
                '<p>No posts in your feed yet. Follow some users or create your own post!</p>' :
                '<p>No public posts to display. Try logging in or registering.</p>';
            return;
        }
        posts.forEach(post => {
            const postElement = createPostElement(post);
            containerEl.appendChild(postElement);
        });
    }

    function createPostElement(post) {
        const postElement = document.createElement('div');
        postElement.className = 'post';
        postElement.dataset.postId = post.id;

        const authorUsernameEscaped = escapeHTML(post.author_username);
        const postBodyEscaped = escapeHTML(post.body);

        postElement.innerHTML = `
            <div class="post-header">
                <img src="${escapeHTML(post.author_profile_pic) || 'https://via.placeholder.com/40?text=A'}" alt="${authorUsernameEscaped}" class="post-author-avatar">
                <div class="post-author-info">
                    <a href="profile.html?username=${encodeURIComponent(post.author_username)}" class="author-username">${authorUsernameEscaped}</a>
                    <div class="post-timestamp">${formatTimestamp(post.timestamp)}</div>
                </div>
                ${AppState.currentUser && AppState.currentUser.id === post.user_id ? 
                    `<button class="delete-post-btn" title="Delete post" data-post-id="${post.id}">&times;</button>` : ''}
            </div>
            <div class="post-body">${postBodyEscaped}</div>
            <div class="post-actions">
                <button class="action-button like-btn ${post.is_liked_by_current_user ? 'liked' : ''}" data-post-id="${post.id}">
                    ${post.is_liked_by_current_user ? 'Unlike' : 'Like'} (${post.likes_count})
                </button>
                <button class="action-button reply-btn" data-post-id="${post.id}" title="View replies / Reply (Not implemented)">
                    Reply (${post.replies_count})
                </button>
            </div>
        `;

        const likeBtn = postElement.querySelector('.like-btn');
        if (likeBtn) {
            likeBtn.addEventListener('click', () => handleLikeToggle(post.id, likeBtn));
        }

        const deleteBtn = postElement.querySelector('.delete-post-btn');
        if (deleteBtn) {
            deleteBtn.addEventListener('click', () => handleDeletePost(post.id, postElement));
        }
        
        const replyBtn = postElement.querySelector('.reply-btn');
        if (replyBtn) {
            replyBtn.addEventListener('click', () => {
                alert(`Reply functionality for post ID ${post.id} is not fully implemented. View full thread to reply.`);
            });
        }
        return postElement;
    }
    
    async function handleLikeToggle(postId, buttonElement) {
        if (!AppState.currentToken) {
            alert('Please login to like posts.');
            return;
        }
        try {
            const result = await request(`/posts/${postId}/like`, 'POST');
            buttonElement.textContent = `${result.liked ? 'Unlike' : 'Like'} (${result.likes_count})`;
            buttonElement.classList.toggle('liked', result.liked);
        } catch (error) {
            console.error('Error liking/unliking post:', error);
            alert(`Error: ${error.message || 'Could not update like.'}`);
        }
    }

    async function handleDeletePost(postId, postElementToRemove) {
        if (!AppState.currentToken || !AppState.currentUser) {
            alert('Please login to delete posts.');
            return;
        }
        if (confirm('Are you sure you want to delete this post? This action cannot be undone.')) {
            try {
                await request(`/posts/${postId}`, 'DELETE');
                postElementToRemove.remove(); 
            } catch (error) {
                console.error('Error deleting post:', error);
                alert(`Error deleting post: ${error.message || 'Could not delete post.'}`);
            }
        }
    }

    if (submitPostButton && postBodyTextarea) {
        submitPostButton.addEventListener('click', async () => {
            if (!AppState.currentToken) {
                alert("Please login to create a post.");
                return;
            }
            const body = postBodyTextarea.value.trim();
            if (!body) {
                alert('Post cannot be empty.');
                return;
            }
            if (body.length > MAX_CHARS) {
                alert(`Post exceeds ${MAX_CHARS} characters.`);
                return;
            }

            try {
                await request('/posts', 'POST', { body });
                postBodyTextarea.value = ''; 
                if(charCountDisplay) charCountDisplay.textContent = `0/${MAX_CHARS}`; 
                if(submitPostButton) submitPostButton.disabled = false; 
                loadFeedPostsGlobally(); 
            } catch (error) {
                console.error('Error creating post:', error);
                alert(`Error creating post: ${error.message || 'Could not create post.'}`);
            }
        });
    }

    if (document.getElementById('feed-section')) {
        loadFeedPostsGlobally();
    }
});
EOF
echo "Created $BASE_DIR/frontend/js/app.js"

# frontend/js/profile.js
cat << 'EOF' > "$BASE_DIR/frontend/js/profile.js"
document.addEventListener('DOMContentLoaded', () => {
    const profileHeaderContainer = document.getElementById('profile-header-content');
    const userPostsContainer = document.getElementById('user-posts-container');
    const followUnfollowButtonEl = document.getElementById('follow-unfollow-profile-button');

    const params = new URLSearchParams(window.location.search);
    const viewedUsername = params.get('username');

    async function loadUserProfile() {
        if (!viewedUsername) {
            if(profileHeaderContainer) profileHeaderContainer.innerHTML = "<p class='error-text'>No username specified in URL (e.g., ?username=test).</p>";
            if(userPostsContainer) userPostsContainer.innerHTML = ""; 
            return;
        }
        if(profileHeaderContainer) profileHeaderContainer.innerHTML = '<p class="loading-text">Loading profile...</p>';

        try {
            const profileData = await request(`/users/${encodeURIComponent(viewedUsername)}`); 
            renderProfileHeader(profileData);
            loadUserPagePosts(profileData.username); 

            if (AppState.currentUser && AppState.currentUser.id !== profileData.id) {
                if(followUnfollowButtonEl) {
                    followUnfollowButtonEl.style.display = 'inline-block';
                    updateFollowButtonState(profileData.is_followed_by_current_user); 
                    followUnfollowButtonEl.dataset.userIdToFollow = profileData.id;
                    
                    const newFollowButton = followUnfollowButtonEl.cloneNode(true);
                    followUnfollowButtonEl.parentNode.replaceChild(newFollowButton, followUnfollowButtonEl);
                    document.getElementById('follow-unfollow-profile-button').addEventListener('click', handleFollowToggle);
                }
            } else {
                if(followUnfollowButtonEl) followUnfollowButtonEl.style.display = 'none';
            }

        } catch (error) {
            const safeViewedUsername = escapeHTML(viewedUsername);
            if(profileHeaderContainer) profileHeaderContainer.innerHTML = `<p class="error-text">Error loading profile for ${safeViewedUsername}: ${error.message || 'Could not fetch profile.'}</p>`;
            if(userPostsContainer) userPostsContainer.innerHTML = "";
            console.error('Error loading profile:', error);
        }
    }

    function renderProfileHeader(profile) {
        if(!profileHeaderContainer) return;
        const usernameEscaped = escapeHTML(profile.username);
        const bioEscaped = escapeHTML(profile.bio);

        profileHeaderContainer.innerHTML = `
            <img src="${escapeHTML(profile.profile_picture) || 'https://via.placeholder.com/100?text=P'}" alt="${usernameEscaped}'s profile picture" class="profile-avatar">
            <h2>${usernameEscaped}</h2>
            <p class="profile-bio">${bioEscaped || 'No bio yet.'}</p>
            <div class="profile-stats">
                <span><strong>${profile.posts_count !== undefined ? profile.posts_count : '-'}</strong> posts</span>
                <span><strong>${profile.followers_count}</strong> followers</span>
                <span><strong>${profile.following_count}</strong> following</span>
            </div>
        `;
    }

    function updateFollowButtonState(isFollowing) {
        const btn = document.getElementById('follow-unfollow-profile-button');
        if(!btn) return;
        if (isFollowing) {
            btn.textContent = 'Unfollow';
            btn.classList.add('following', 'secondary-button');
            btn.classList.remove('primary-button');
        } else {
            btn.textContent = 'Follow';
            btn.classList.remove('following', 'secondary-button');
            btn.classList.add('primary-button');
        }
    }

    async function handleFollowToggle() {
        const btn = document.getElementById('follow-unfollow-profile-button');
        if (!AppState.currentToken) {
            alert('Please login to follow users.');
            return;
        }
        const userIdToFollow = btn.dataset.userIdToFollow;
        const isCurrentlyFollowing = btn.classList.contains('following');
        const endpoint = `/users/${userIdToFollow}/${isCurrentlyFollowing ? 'unfollow' : 'follow'}`;

        try {
            await request(endpoint, 'POST');
            loadUserProfile(); 
        } catch (error) {
            alert(`Error: ${error.message || 'Could not update follow status.'}`);
            console.error('Follow/unfollow error:', error);
        }
    }

    async function loadUserPagePosts(usernameForPosts) {
        if (!userPostsContainer) return;
        userPostsContainer.innerHTML = '<p class="loading-text">Loading posts...</p>';
        try {
            const data = await request(`/users/${encodeURIComponent(usernameForPosts)}/posts`);
            renderProfilePosts(data.posts);
        } catch (error) {
            userPostsContainer.innerHTML = `<p class="error-text">Error loading ${escapeHTML(usernameForPosts)}'s posts: ${error.message || 'Could not fetch posts.'}</p>`;
            console.error('Error loading user posts:', error);
        }
    }

    function renderProfilePosts(posts) { 
        if (!userPostsContainer) return;
        userPostsContainer.innerHTML = '';
        if (!posts || posts.length === 0) {
            userPostsContainer.innerHTML = '<p>This user has no posts yet.</p>';
            return;
        }
        posts.forEach(post => {
            const postElement = createPostElementForProfile(post);
            userPostsContainer.appendChild(postElement);
        });
    }

    function createPostElementForProfile(post) { 
        const postElement = document.createElement('div');
        postElement.className = 'post';
        postElement.dataset.postId = post.id;
        
        const authorUsernameEscaped = escapeHTML(post.author_username);
        const postBodyEscaped = escapeHTML(post.body);

        postElement.innerHTML = `
            <div class="post-header">
                <img src="${escapeHTML(post.author_profile_pic) || 'https://via.placeholder.com/40?text=A'}" alt="${authorUsernameEscaped}" class="post-author-avatar">
                <div class="post-author-info">
                     <a href="profile.html?username=${encodeURIComponent(post.author_username)}" class="author-username">${authorUsernameEscaped}</a>
                    <div class="post-timestamp">${formatTimestamp(post.timestamp)}</div>
                </div>
                ${AppState.currentUser && AppState.currentUser.id === post.user_id ? 
                    `<button class="delete-post-btn" title="Delete post" data-post-id="${post.id}">&times;</button>` : ''}
            </div>
            <div class="post-body">${postBodyEscaped}</div>
            <div class="post-actions">
                <button class="action-button like-btn ${post.is_liked_by_current_user ? 'liked' : ''}" data-post-id="${post.id}">
                    ${post.is_liked_by_current_user ? 'Unlike' : 'Like'} (${post.likes_count})
                </button>
                <button class="action-button reply-btn" data-post-id="${post.id}" title="View replies / Reply (Not implemented)">
                    Reply (${post.replies_count})
                </button>
            </div>
        `;

        const likeBtn = postElement.querySelector('.like-btn');
        if (likeBtn) {
            likeBtn.addEventListener('click', () => handleProfileLikeToggle(post.id, likeBtn));
        }
        const deleteBtn = postElement.querySelector('.delete-post-btn');
        if (deleteBtn) {
            deleteBtn.addEventListener('click', () => handleProfileDeletePost(post.id, postElement));
        }
        const replyBtn = postElement.querySelector('.reply-btn');
        if (replyBtn) {
            replyBtn.addEventListener('click', () => {
                alert(`Reply functionality for post ID ${post.id} is not fully implemented yet.`);
            });
        }
        return postElement;
    }
    
    async function handleProfileLikeToggle(postId, buttonElement) {
        if (!AppState.currentToken) {
            alert('Please login to like posts.');
            return;
        }
        try {
            const result = await request(`/posts/${postId}/like`, 'POST');
            buttonElement.textContent = `${result.liked ? 'Unlike' : 'Like'} (${result.likes_count})`;
            buttonElement.classList.toggle('liked', result.liked);
        } catch (error) {
            console.error('Error liking/unliking post:', error);
            alert(`Error: ${error.message || 'Could not update like.'}`);
        }
    }

    async function handleProfileDeletePost(postId, postElementToRemove) {
        if (!AppState.currentToken || !AppState.currentUser) {
            alert('Please login to delete posts.');
            return;
        }
        if (confirm('Are you sure you want to delete this post? This action cannot be undone.')) {
            try {
                await request(`/posts/${postId}`, 'DELETE');
                postElementToRemove.remove();
                loadUserProfile(); 
            } catch (error) {
                console.error('Error deleting post:', error);
                alert(`Error deleting post: ${error.message || 'Could not delete post.'}`);
            }
        }
    }

    if (viewedUsername) {
        loadUserProfile();
    } else if (profileHeaderContainer) {
        profileHeaderContainer.innerHTML = '<h1>User profile not specified.</h1> <p>Please provide a username in the URL (e.g., profile.html?username=testuser).</p>';
    }
});
EOF
echo "Created $BASE_DIR/frontend/js/profile.js"

# --- Create Docs Structure ---
echo "Creating docs structure inside $BASE_DIR..."
mkdir -p "$BASE_DIR/docs"

# --- Create Docs Files ---

# .gitignore (at project root relative to BASE_DIR, so just .gitignore)
cat << 'EOF' > "$BASE_DIR/.gitignore"
# Python
__pycache__/
*.py[cod]
*.egg
*.egg-info/
.DS_Store
# Virtual environments
env/
venv/
.venv/
# Instance folder (contains DB, local config, sensitive files for dev)
backend/instance/
# IDE / Editor specific files
.vscode/
.idea/
*.sublime-project
*.sublime-workspace
# Operating System files
Thumbs.db
ehthumbs.db
Desktop.ini
# Log files
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*
# dotenv environment variable files
backend/.env
EOF
echo "Created $BASE_DIR/.gitignore"

# README.md (Top-level)
cat << 'EOF' > "$BASE_DIR/README.md"
# Threads Clone Project

This project is a simplified, educational clone of Meta's Threads application. It's built with a Python/Flask backend and a vanilla JavaScript frontend.

## Overview

The goal is to demonstrate the core functionalities of a social media application, including:
*   User authentication (registration, login)
*   Creating and viewing posts (text-based "threads")
*   A main feed of posts
*   Liking posts
*   Following/unfollowing users
*   User profiles with their posts
*   Basic user search

This project is **not intended for production use** as it simplifies many complex aspects like security, scalability, and advanced features.

## Quick Links

*   **Detailed Project Documentation & Setup:** [`docs/README.md`](./docs/README.md)
*   **Developer Guide:** [`docs/DEVELOPER_GUIDE.md`](./docs/DEVELOPER_GUIDE.md)
*   **API Documentation:** [`docs/API_DOCS.md`](./docs/API_DOCS.md)

## To Get Started

1.  If you used the `create_initial_project.sh` script (this script), the project is already created.
2.  Otherwise, clone this repository.
3.  Navigate to the `docs/` directory and follow the setup instructions in `docs/README.md`.

## Tech Stack

*   **Backend:** Python, Flask, Flask-SQLAlchemy, SQLite (default)
*   **Frontend:** HTML, CSS, Vanilla JavaScript
*   **API:** RESTful

---
**Disclaimer:** This project is for educational purposes only and is not affiliated with Meta Platforms, Inc. or Threads.
EOF
echo "Created $BASE_DIR/README.md (Top-level)"

# docs/README.md
cat << 'EOF' > "$BASE_DIR/docs/README.md"
# Threads Clone Project - Documentation

This document provides an overview of the Threads Clone project, setup instructions, and how to run the application.

## 1. Features (Implemented MVP)

*   **User Management:**
    *   User registration with username, email, and password.
    *   User login.
    *   Authenticated user context (`/api/me`).
*   **Social Graph:**
    *   Follow and unfollow other users.
    *   View user profiles with follower/following counts and their posts.
*   **Content Creation & Interaction:**
    *   Create text-based posts (up to 500 characters).
    *   View a main feed of posts from followed users and self (for logged-in users).
    *   View a public feed of all top-level posts (for unauthenticated API key access).
    *   Like and unlike posts.
    *   View post details including replies (replies are posts with `parent_id`).
    *   Delete own posts.
*   **Discovery:**
    *   Basic search for users by username.

## 2. Tech Stack

*   **Backend:**
    *   Python 3.8+
    *   Flask (web framework)
    *   Flask-SQLAlchemy (ORM)
    *   Flask-Migrate (for database migrations - optional setup shown)
    *   Flask-CORS (for cross-origin requests during development)
    *   SQLite (default database for simplicity)
    *   Werkzeug (for password hashing)
    *   `python-dotenv` (for managing environment variables)
*   **Frontend:**
    *   HTML5
    *   CSS3 (with basic mobile responsiveness)
    *   Vanilla JavaScript (ES6+)
*   **API Style:** RESTful

## 3. Project Structure Overview

Refer to the main `threads_clone/README.md` or `docs/DEVELOPER_GUIDE.md` for the detailed project structure.

## 4. Setup and Running the Application

### Prerequisites

*   Python 3.8 or higher installed.
*   `pip` (Python package installer).
*   A virtual environment tool (like `venv`, highly recommended).
*   A modern web browser.

### Backend Setup

1.  **(If not using the .sh script) Clone the Repository:**
    ```bash
    # git clone <repository_url> # Or download and extract the ZIP
    # cd threads_clone
    ```
    If you ran the script that created this project, you are already in the `threads_clone` directory.

2.  **Navigate to Backend Directory:**
    ```bash
    cd backend 
    # (Should be threads_clone/backend/ from project root)
    ```

3.  **Create and Activate Virtual Environment:**
    *   On macOS/Linux:
        ```bash
        python3 -m venv venv
        source venv/bin/activate
        ```
    *   On Windows:
        ```bash
        python -m venv venv
        venv\Scripts\activate
        ```

4.  **Install Dependencies:**
    ```bash
    pip install -r requirements.txt
    ```

5.  **Create/Verify Environment File (`.env`):**
    In the `threads_clone/backend/` directory, ensure a file named `.env` exists with the following content. **Customize the secret keys!**
    (The script that generated this project also created `backend/.env_INSTRUCTIONS.txt` with this info.)
    ```env
    SECRET_KEY='your_very_secret_flask_key_please_change_me'
    API_KEY='your_super_secret_api_key_for_public_endpoints_change_me'
    # SQLALCHEMY_DATABASE_URI='sqlite:///instance/threads.db' # Default, if not set
    # Optional: For PostgreSQL, replace the above with (after setting up PostgreSQL):
    # SQLALCHEMY_DATABASE_URI='postgresql://youruser:yourpassword@localhost:5432/threads_db_name'
    ```
    *The `backend/instance` folder and `threads.db` SQLite file will be created automatically by `config.py` and `app/__init__.py` if they don't exist when the app first runs.*

6.  **(Optional but Recommended for Schema Changes) Database Migrations with Flask-Migrate:**
    If you plan to evolve the database schema, Flask-Migrate is useful.
    *   Ensure your virtual environment is activated and you are in the `threads_clone/backend/` directory.
    *   Set the Flask app environment variable (do this in your terminal session):
        *   macOS/Linux: `export FLASK_APP=run.py`
        *   Windows: `set FLASK_APP=run.py`
    *   Initialize migrations (only once per project, if `migrations` folder doesn't exist):
        ```bash
        flask db init
        ```
    *   Create an initial migration (or after any model changes):
        ```bash
        flask db migrate -m "Initial migration with User, Post, Like models"
        ```
    *   Apply the migration to the database:
        ```bash
        flask db upgrade
        ```
    *For this project, `db.create_all()` in `app/__init__.py` will also create the tables on the first run if migrations aren't used, which is simpler for a quick start with SQLite.*

7.  **Run the Backend Server:**
    From the `threads_clone/backend/` directory (with virtual env active):
    ```bash
    python run.py
    ```
    The backend API should now be running, typically on `http://localhost:5001` (or `http://0.0.0.0:5001`).

### Frontend Usage

1.  **No Build Step Required:** The frontend is composed of static HTML, CSS, and JavaScript files.
2.  **Open in Browser:**
    Navigate to the `threads_clone/frontend/` directory in your file explorer and open `index.html` in your web browser.
    *   Example path if you drag `index.html` to your browser: `file:///path/to/your/threads_clone/frontend/index.html`
3.  **Interact:**
    *   Register a new user or log in.
    *   Create posts, view the feed, like posts, follow users, and explore profiles.

## 5. Important Notes for Testing

*   **Backend First:** Ensure the backend server (`python run.py`) is running and accessible before you try to use the frontend in your browser.
*   **Console Logs:** Open your browser's developer console (usually F12 or Ctrl+Shift+I/Cmd+Option+I) to see JavaScript logs, network requests, and any errors from the frontend.
*   **Network Tab:** The "Network" tab in your browser's developer tools will show all API requests made by the frontend to the backend, their status, and the data exchanged. This is very helpful for debugging API interactions.
*   **`.env` File:** Double-check that `backend/.env` is created correctly and that `config.py` can find it. The script attempts to load it from the `backend/` directory.
*   **Security:** The authentication mechanism (`Authorization: Bearer <user_id>`) is **highly insecure** and for demonstration purposes only. In a real application, use robust token-based authentication like JWT.
*   **Scalability:** SQLite is not suitable for production applications or high load. For more robust testing or small production, consider PostgreSQL. The single-server Flask setup with its development server or even a basic Gunicorn setup will not handle "millions of accesses" as a production system would.
*   **Error Handling:** Error handling is basic. Production apps require more comprehensive error management and user feedback.

See `docs/DEVELOPER_GUIDE.md` for more technical details and `docs/API_DOCS.md` for API endpoint specifications.
EOF
echo "Created $BASE_DIR/docs/README.md"

# docs/DEVELOPER_GUIDE.md
cat << 'EOF' > "$BASE_DIR/docs/DEVELOPER_GUIDE.md"
# Developer Guide - Threads Clone

This guide provides technical information for developers working on or extending the Threads Clone project.

## 1. Architecture Overview

The project follows a traditional client-server architecture with a distinct backend API and a static frontend.

*   **Backend (Flask Application in `threads_clone/backend/`):**
    *   **`app/`:** Core application module.
        *   `__init__.py`: Flask app factory; initializes extensions (SQLAlchemy, Migrate, CORS). Contains `db.create_all()` for initial table setup if not using migrations exclusively.
        *   `models.py`: Defines SQLAlchemy ORM models (`User`, `Post`, `Like`) and the `followers` association table. Includes hybrid properties for derived counts (e.g., `likes_count`).
        *   `routes.py`: Contains all API endpoint definitions using a Flask Blueprint. Handles request parsing, business logic execution (interacting with models), and JSON response generation.
        *   `auth.py`: Implements simplified authentication decorators (`@protected_route`, `@require_login`) and a basic login helper. **This is a placeholder and needs replacement for production.**
    *   `config.py`: Manages application configuration, loaded from environment variables (`.env` file) and defaults. Sets up the instance folder path.
    *   `run.py`: Entry script to start the Flask development server.
    *   `instance/`: This folder is created by `config.py` if it doesn't exist. It's intended for instance-specific files like the SQLite database (`threads.db`) or local configuration overrides. It's gitignored.
    *   `requirements.txt`: Lists Python dependencies.

*   **Frontend (Static Files in `threads_clone/frontend/`):**
    *   **HTML Files (`index.html`, `login.html`, `register.html`, `profile.html`):** Structure the different views of the application.
    *   **CSS (`css/style.css`):** Contains all styling rules, including basic mobile responsiveness using media queries. Organized with general styles, component-specific styles, and utility classes.
    *   **JavaScript (`js/`):**
        *   `api.js`: A reusable module for making `fetch` requests to the backend API. Handles setting authorization headers (using `AppState` from `common.js`) and basic error parsing.
        *   `common.js`: Contains shared UI functions and a simple global `AppState` (for `currentUser` and `currentToken`). Handles updating navigation based on auth state, and global search bar logic. Initializes common UI elements on page load.
        *   `auth.js`: Handles logic for the login and registration forms, including form submission and interaction with the `api.js` module. Updates global auth state on success.
        *   `app.js`: Script specific to `index.html`. Manages the main post feed, post creation, and interactions on the feed (likes, deletes).
        *   `profile.js`: Script specific to `profile.html`. Manages displaying user profile information, their posts, and follow/unfollow actions.

## 2. Backend Deep Dive

*   **Models (`models.py`):**
    *   Relationships are defined using SQLAlchemy's `db.relationship`. Backrefs simplify navigation (e.g., `post.author`, `user.posts`).
    *   The `followers` table facilitates a many-to-many self-referential relationship on the `User` model for the follow system.
    *   Hybrid properties (`@hybrid_property`) like `posts_count`, `followers_count`, `following_count`, `likes_count`, `replies_count` provide convenient ways to access derived data directly on model instances.
    *   `to_dict()` methods on models control the JSON serialization for API responses. They conditionally include data based on context (e.g., `current_user_obj` is passed to determine `is_followed_by_current_user` or `is_liked_by_current_user`).
*   **Authentication (`auth.py` & `routes.py`):**
    *   `@protected_route`: A decorator that checks for an `Authorization` header. It attempts to parse a `Bearer <user_id>` token (highly insecure, demo only) or an `ApiKey <key>`. It sets `g.current_user` (if Bearer token is valid user ID) and `g.is_api_key_auth`. It allows routes to proceed even if no user is found, letting the route logic handle public vs. private access.
    *   `@require_login`: A stricter decorator that builds upon `@protected_route` and ensures `g.current_user` is set (i.e., user must be logged in via Bearer token). If not, it returns a 401.
    *   The `/login` route returns the `user_id` as the "token". **This is a critical security flaw for production.**
    *   **Production TODO:** Implement JWT (JSON Web Tokens) for stateless, secure authentication. This involves token generation on login, token verification in middleware/decorators, handling token expiration, and possibly refresh tokens.
*   **Error Handling:** API routes return JSON responses with error messages and appropriate HTTP status codes (e.g., 400, 401, 403, 404, 409, 500). Logging is basic; production apps would use more structured logging.
*   **Database:** SQLite is used for ease of setup. For production, switch to PostgreSQL or MySQL. `Flask-Migrate` is included for managing schema changes systematically if you choose to use it beyond the initial `db.create_all()`.

## 3. Frontend Deep Dive

*   **API Interaction (`api.js`):** All backend communication goes through the `request` function. It centralizes API call logic, making it easier to manage base URLs, headers (automatically including the Bearer token from `AppState`), and parsing API error responses.
*   **State Management (`common.js` & Local Storage):**
    *   The logged-in user's "token" (user ID) and basic user object are stored in `localStorage` for persistence across sessions.
    *   `common.js` defines a global `AppState` object which holds the `currentUser` and `currentToken`, kept in sync with `localStorage` via `updateGlobalAuthState()`. This allows different JS modules to access the current auth state.
*   **Dynamic Content Rendering:** JavaScript is heavily used to:
    *   Fetch data from the API using `api.js`.
    *   Dynamically create and manipulate DOM elements (e.g., posts, profile info, search results) using template literals and DOM methods.
    *   Update the UI in response to user interactions (e.g., liking a post, submitting a new post, following a user) and API responses.
    *   `escapeHTML()` in `common.js` is used to sanitize user-generated content before inserting it into the DOM to prevent XSS.
*   **Reusability (`common.js`):**
    *   `initializeCommonUI()`: Called on page load by every page that includes `common.js`. It sets up shared elements like the navigation bar's auth state and the global search bar functionality.
    *   `updateCommonNavUI()`: Adjusts navigation links (Login/Register vs. Profile/Logout) based on the current login status in `AppState`.
    *   `handleGlobalSearch()` and `renderGlobalSearchResults()`: Provide debounced, dynamic search functionality for the header search bar.
    *   `displayMessage()`: A utility for showing success/error messages, typically within forms.
    *   `formatTimestamp()`: Utility for making timestamps more readable.
*   **Event Handling:** Event listeners are attached to buttons, forms, and input fields to trigger JavaScript functions for user interactions. For dynamically added elements (like delete buttons on posts), event listeners are added when the element is created.
*   **Mobile Responsiveness (`style.css`):** Achieved through CSS media queries, adjusting layout, font sizes, and spacing for smaller screens.

## 4. Adding a New Feature (Example Workflow)

Let's say you want to add **"Editing Own Posts"**:

1.  **Backend - Model:** No changes likely needed to `Post` model itself unless you want to track edit history (e.g., `last_edited_at` timestamp).
2.  **Backend - Routes:**
    *   In `routes.py`, create a new API endpoint: `PUT /api/posts/<int:post_id>`
    *   This route must be `@require_login`.
    *   Verify the `g.current_user` is the `author` of the post.
    *   Accept a new `body` in the request JSON.
    *   Update the post's `body` and commit to the database.
    *   Return the updated post object.
3.  **Frontend - UI:**
    *   In `createPostElement` (in `app.js` and `profile.js`), add an "Edit" button next to the "Delete" button, visible only if `AppState.currentUser.id === post.user_id`.
4.  **Frontend - JS:**
    *   When the "Edit" button is clicked:
        *   Could replace the post body display with a textarea pre-filled with current body.
        *   Add "Save" and "Cancel" buttons.
        *   On "Save", make a `PUT` request to `/api/posts/<post_id>` with the new body using `api.js`.
        *   On success, update the post display in the DOM with the new body from the API response.
        *   On "Cancel", revert to displaying the original body.
    *   Alternatively, the "Edit" button could navigate to a dedicated edit page or open a modal form.
5.  **Documentation:**
    *   Update `API_DOCS.md` with the new `PUT /api/posts/<post_id>` endpoint.
    *   Update this `DEVELOPER_GUIDE.md` if the feature introduces significant new patterns.

## 5. Coding Conventions & Best Practices (Suggestions)

*   **Python:** Follow PEP 8 guidelines. Use linters like Flake8 or Pylint.
*   **JavaScript:** Follow a consistent style (e.g., Airbnb, StandardJS, or Prettier). Use linters like ESLint.
*   **Commit Messages:** Write clear, concise, and descriptive Git commit messages.
*   **Modularity:** Keep functions and modules focused on a single responsibility.
*   **Comments:** Comment complex logic, non-obvious code sections, or "why" something is done a certain way.
*   **Security:**
    *   **Input Validation:** Validate all user input on both frontend (for UX) and backend (for security).
    *   **Output Encoding:** Use `escapeHTML()` or similar techniques when inserting user-generated content into the DOM to prevent XSS.
    *   **Authentication & Authorization:** The current auth is a placeholder. Implement robust JWT authentication. Ensure proper authorization checks for all sensitive actions.
*   **Error Handling:** Provide clear error messages to the user. Log detailed errors on the backend for debugging.
*   **Testing:** Crucial for larger applications.
    *   **Backend:** Unit tests for models and utility functions. Integration tests for API endpoints.
    *   **Frontend:** Consider unit tests for complex JS logic and end-to-end tests (e.g., using Playwright, Cypress) for critical user flows.

## 6. Key Future Improvements & TODOs (Beyond MVP)

*   **Robust Authentication (CRITICAL):** Implement JWT-based authentication.
*   **Media Uploads & Handling:** Allow image/video attachments to posts (requires backend file handling, storage like S3, frontend upload UI).
*   **Real-time Features:** Use WebSockets for live feed updates, notifications, and potentially DMs.
*   **Advanced Feed Algorithms:** Develop a "For You" page with personalized recommendations (complex, involves ML).
*   **Notifications System:** In-app and (for native apps) push notifications.
*   **Enhanced Search:** Full-text search for posts, topics, potentially using a dedicated search engine like Elasticsearch or Meilisearch.
*   **Direct Messaging (DMs).**
*   **Content Moderation Tools & Policies.**
*   **Scalable Infrastructure:** For higher loads, migrate to PostgreSQL/MySQL, implement caching (Redis), and eventually consider a microservices architecture. Use a production WSGI server (Gunicorn, uWSGI) and a reverse proxy (Nginx).
*   **Frontend Framework/Library:** For more complex and maintainable UIs, adopt a modern JavaScript framework/library (React, Vue, Svelte, Angular).
*   **Comprehensive Testing Suite.**
*   **CI/CD Pipelines for automated building, testing, and deployment.**
*   **Accessibility (a11y):** Ensure the application is usable by people with disabilities (ARIA attributes, keyboard navigation, color contrast).
*   **Internationalization (i18n) & Localization (l10n):** Support for multiple languages.
EOF
echo "Created $BASE_DIR/docs/DEVELOPER_GUIDE.md"

# docs/API_DOCS.md
cat << 'EOF' > "$BASE_DIR/docs/API_DOCS.md"
# Threads Clone API Documentation

**Base URL:** `http://localhost:5001/api`

**Authentication:**
Most protected endpoints require an `Authorization` header. For this demo, it's:
`Authorization: Bearer <user_id>`
Where `<user_id>` is the ID of the logged-in user.
**WARNING: This is a simplified, insecure mechanism for development only. Production systems must use proper token-based authentication (e.g., JWT).**

Certain public GET endpoints might work without Bearer token authentication if an `API_KEY` (configured in `backend/.env`) is provided:
`Authorization: ApiKey <CONFIGURED_API_KEY>`
Or they might be accessible without any auth if the route's `@protected_route` decorator is configured to allow it and `g.current_user` is not strictly checked within the route.

---

## 1. Authentication Endpoints

### 1.1. Register User
*   **Endpoint:** `POST /register`
*   **Description:** Creates a new user account.
*   **Authentication:** None required.
*   **Request Body (JSON):**
    ```json
    {
        "username": "newuser", // Min 3, Max 64 chars
        "email": "newuser@example.com", // Valid email format
        "password": "securepassword123" // Min 6 chars
    }
    ```
*   **Success Response (201):**
    ```json
    {
        "message": "User registered successfully",
        "token": "1", // User ID, to be used as Bearer token in this demo
        "user": { /* user object, including email and is_followed_by_current_user: false */ }
    }
    ```
*   **Error Responses:**
    *   `400 Bad Request`: Missing fields, invalid field length or format.
    *   `409 Conflict`: Username or email already taken.
    *   `500 Internal Server Error`: Database or other server error.

### 1.2. Login User
*   **Endpoint:** `POST /login`
*   **Description:** Authenticates a user and returns a "token".
*   **Authentication:** None required.
*   **Request Body (JSON):**
    ```json
    {
        "username": "testuser",
        "password": "password123"
    }
    ```
*   **Success Response (200):**
    ```json
    {
        "message": "Login successful",
        "token": "1", // User ID, to be used as Bearer token
        "user": { /* user object, including email and is_followed_by_current_user: false */ }
    }
    ```
*   **Error Responses:**
    *   `400 Bad Request`: Missing fields.
    *   `401 Unauthorized`: Invalid username or password.

### 1.3. Get Current User Details
*   **Endpoint:** `GET /me`
*   **Description:** Retrieves details for the currently authenticated (logged-in) user.
*   **Authentication:** `Bearer <user_id>` required (via `@require_login`).
*   **Success Response (200):** User object.
    ```json
    {
        "id": 1,
        "username": "testuser",
        "email": "testuser@example.com", // Email included for 'me'
        "bio": "My bio here",
        "profile_picture": null, // URL string or null
        "created_at": "2023-10-27T10:00:00Z",
        "followers_count": 5,
        "following_count": 10,
        "posts_count": 20,
        "is_followed_by_current_user": false // Always false for self
    }
    ```
*   **Error Responses:**
    *   `401 Unauthorized`: Authentication failed or token invalid.

---

## 2. User Endpoints

### 2.1. Get User Profile
*   **Endpoint:** `GET /users/<username>`
*   **Description:** Retrieves public profile information for a user. Case-insensitive username matching.
*   **Authentication:** Optional (`Bearer <user_id>` or `ApiKey <key>`). If authenticated as a user, `is_followed_by_current_user` field is included in the response.
*   **Success Response (200):** User object.
    ```json
    {
        "id": 2,
        "username": "anotheruser",
        "bio": "Another user's bio",
        "profile_picture": "url/to/image.jpg",
        "created_at": "2023-10-28T12:00:00Z",
        "followers_count": 15,
        "following_count": 3,
        "posts_count": 7,
        "is_followed_by_current_user": true // Present and accurate if authenticated user is viewing
    }
    ```
*   **Error Responses:**
    *   `404 Not Found`: User with the given username not found.

### 2.2. Search Users
*   **Endpoint:** `GET /users/search`
*   **Description:** Searches for users by username (case-insensitive, partial match).
*   **Authentication:** Optional. `is_followed_by_current_user` in results depends on authenticated user context.
*   **Query Parameters:**
    *   `q` (string, required): The search query string (min 1 character recommended).
*   **Success Response (200):** Array of user objects (structure similar to Get User Profile, email excluded).
    ```json
    [
        { /* user object */ },
        { /* user object */ }
    ]
    ```

### 2.3. Follow User
*   **Endpoint:** `POST /users/<user_id_to_action>/follow`
*   **Description:** Allows the authenticated user to follow another user specified by their ID.
*   **Authentication:** `Bearer <user_id>` required (via `@require_login`).
*   **Success Response (200):**
    ```json
    {
        "message": "You are now following target_username",
        "is_following": true // Indicates the new state
    }
    ```
*   **Error Responses:**
    *   `400 Bad Request`: Already following, or trying to follow self.
    *   `401 Unauthorized`.
    *   `404 Not Found`: Target user (user_id_to_action) not found.

### 2.4. Unfollow User
*   **Endpoint:** `POST /users/<user_id_to_action>/unfollow`
*   **Description:** Allows the authenticated user to unfollow another user specified by their ID.
*   **Authentication:** `Bearer <user_id>` required (via `@require_login`).
*   **Success Response (200):**
    ```json
    {
        "message": "You have unfollowed target_username",
        "is_following": false // Indicates the new state
    }
    ```
*   **Error Responses:**
    *   `400 Bad Request`: Not currently following this user.
    *   `401 Unauthorized`.
    *   `404 Not Found`: Target user not found.

### 2.5. Get User's Followers
*   **Endpoint:** `GET /users/<username>/followers`
*   **Description:** Retrieves a list of users following the specified user. Case-insensitive username.
*   **Authentication:** Optional. Contextual fields in results (like `is_followed_by_current_user` for each follower) depend on auth.
*   **Success Response (200):** Array of user objects.
*   **Error Responses:**
    *   `404 Not Found`: User not found.

### 2.6. Get User's Following
*   **Endpoint:** `GET /users/<username>/following`
*   **Description:** Retrieves a list of users the specified user is following. Case-insensitive username.
*   **Authentication:** Optional. Contextual fields in results depend on auth.
*   **Success Response (200):** Array of user objects.
*   **Error Responses:**
    *   `404 Not Found`: User not found.

---

## 3. Post (Thread) Endpoints

### 3.1. Create Post
*   **Endpoint:** `POST /posts`
*   **Description:** Creates a new post (thread) or a reply to an existing post.
*   **Authentication:** `Bearer <user_id>` required (via `@require_login`).
*   **Request Body (JSON):**
    ```json
    {
        "body": "This is my new thread! (Max 500 chars)",
        "parent_id": null // or integer ID of the post being replied to
    }
    ```
*   **Success Response (201):** Post object.
    ```json
    {
        "id": 101,
        "body": "This is my new thread!",
        "timestamp": "2023-10-27T10:30:00Z",
        "user_id": 1,
        "author_username": "testuser",
        "author_profile_pic": "url/to/pic.jpg",
        "parent_id": null,
        "likes_count": 0,
        "replies_count": 0,
        "is_liked_by_current_user": false // Based on authenticated user creating it
    }
    ```
*   **Error Responses:**
    *   `400 Bad Request`: Empty body, body too long, invalid `parent_id` format.
    *   `401 Unauthorized`.
    *   `404 Not Found`: If `parent_id` is provided but parent post doesn't exist.

### 3.2. Get Posts Feed
*   **Endpoint:** `GET /posts`
*   **Description:** Retrieves a feed of top-level posts.
    *   If authenticated with `Bearer <user_id>`: shows posts from followed users and self.
    *   If authenticated with `ApiKey <key>`: shows a public feed of all top-level posts.
    *   Otherwise: `401 Unauthorized`.
*   **Authentication:** `Bearer <user_id>` OR `ApiKey <key>` required (handled by `@protected_route`).
*   **Query Parameters:**
    *   `page` (int, optional, default: 1): Page number for pagination.
    *   `per_page` (int, optional, default: 10): Number of posts per page.
*   **Success Response (200):** Paginated list of post objects.
    ```json
    {
        "posts": [ /* array of post objects */ ],
        "total_posts": 100,
        "current_page": 1,
        "total_pages": 10
    }
    ```

### 3.3. Get User's Posts
*   **Endpoint:** `GET /users/<username>/posts`
*   **Description:** Retrieves a list of top-level posts made by the specified user. Case-insensitive username. Supports pagination.
*   **Authentication:** Optional. `is_liked_by_current_user` on posts depends on authenticated user context.
*   **Query Parameters:** (Same as Get Posts Feed: `page`, `per_page`)
*   **Success Response (200):** Paginated list of post objects by the user.
*   **Error Responses:**
    *   `404 Not Found`: User not found.

### 3.4. Get Post Details
*   **Endpoint:** `GET /posts/<post_id>`
*   **Description:** Retrieves details for a specific post, including its replies (ordered by timestamp, oldest first).
*   **Authentication:** Optional. Contextual fields (like `is_liked_by_current_user`) depend on auth.
*   **Success Response (200):** Post object with an additional `replies` array.
    ```json
    {
        // ... post fields (as in Create Post response)
        "replies": [
            { /* reply post object (same structure as post) */ },
            { /* another reply post object */ }
        ]
    }
    ```
*   **Error Responses:**
    *   `404 Not Found`: Post not found.

### 3.5. Like/Unlike Post
*   **Endpoint:** `POST /posts/<post_id>/like`
*   **Description:** Toggles the like status for a post by the authenticated user.
*   **Authentication:** `Bearer <user_id>` required (via `@require_login`).
*   **Success Response (200):**
    *   If liked: `{"message": "Post liked", "liked": true, "likes_count": 1}`
    *   If unliked: `{"message": "Post unliked", "liked": false, "likes_count": 0}`
*   **Error Responses:**
    *   `401 Unauthorized`.
    *   `404 Not Found`: Post not found.

### 3.6. Delete Post
*   **Endpoint:** `DELETE /posts/<post_id>`
*   **Description:** Deletes a post if the authenticated user is the author. Deleting a post will also delete its replies and likes due to cascade settings in the model.
*   **Authentication:** `Bearer <user_id>` required (via `@require_login`).
*   **Success Response (200):**
    ```json
    {
        "message": "Post deleted successfully"
    }
    ```
*   **Error Responses:**
    *   `401 Unauthorized`.
    *   `403 Forbidden`: User is not the author of the post.
    *   `404 Not Found`: Post not found.
EOF
echo "Created $BASE_DIR/docs/API_DOCS.md"


# --- Create the Updater Script (`apply_update.sh`) ---
# This script will be created in the current directory (parent of BASE_DIR)
cat << 'EOF' > apply_update.sh
#!/bin/bash

# This script helps update files within the 'threads_clone' project.
# It prompts for the relative path of the file to update and then
# allows pasting the new content.

PROJECT_DIR_NAME="threads_clone" # The name of the project directory

# Check if the script is being run from the directory containing 'threads_clone'
if [ ! -d "./$PROJECT_DIR_NAME" ]; then
    echo "Error: Project directory '$PROJECT_DIR_NAME' not found in the current location ($(pwd))."
    echo "Please run this script from the directory that CONTAINS the '$PROJECT_DIR_NAME' folder."
    exit 1
fi

echo "--- Threads Clone Project File Updater ---"
read -p "Enter the relative path of the file to update (e.g., backend/app/models.py): " TARGET_FILE_RELATIVE

if [ -z "$TARGET_FILE_RELATIVE" ]; then
    echo "No file path entered. Exiting."
    exit 1
fi

# Construct the full path relative to the script's current execution directory
FULL_TARGET_PATH="./$PROJECT_DIR_NAME/$TARGET_FILE_RELATIVE"
TARGET_DIR=$(dirname "$FULL_TARGET_PATH")

# Create parent directories if they don't exist
if [ ! -d "$TARGET_DIR" ]; then
    mkdir -p "$TARGET_DIR" || { echo "Failed to create directory $TARGET_DIR. Exiting."; exit 1; }
    echo "Created directory: $TARGET_DIR"
fi

echo ""
echo "You are about to update/create: $FULL_TARGET_PATH"
echo "Paste the new content below. When finished, type '__EOF__' on a new, empty line and press Enter."
echo "--- BEGIN PASTE ---"

TEMP_CONTENT_FILE=$(mktemp) 

while IFS= read -r line; do
    if [[ "$line" == "__EOF__" ]]; then
        break
    fi
    echo "$line" >> "$TEMP_CONTENT_FILE"
done

if [ -f "$FULL_TARGET_PATH" ]; then
    read -p "File '$FULL_TARGET_PATH' already exists. Overwrite? (y/N): " confirm_overwrite
    if [[ "$confirm_overwrite" != "y" && "$confirm_overwrite" != "Y" ]]; then
        echo "Update cancelled. File not overwritten."
        rm "$TEMP_CONTENT_FILE"
        exit 0
    fi
fi

mv "$TEMP_CONTENT_FILE" "$FULL_TARGET_PATH" || { 
    echo "Error moving content to $FULL_TARGET_PATH. Temporary content is in $TEMP_CONTENT_FILE."
    exit 1; 
}

# If TEMP_CONTENT_FILE still exists (mv failed somehow, or it was empty and mv didn't run)
if [ -f "$TEMP_CONTENT_FILE" ]; then
    rm "$TEMP_CONTENT_FILE"
fi

echo "--- END PASTE ---"
echo "File '$FULL_TARGET_PATH' has been updated successfully."
echo ""
echo "Remember to restart your backend server if backend files were changed."

exit 0
EOF
chmod +x apply_update.sh
echo ""
echo "---------------------------------------------------------------------"
echo "An updater script 'apply_update.sh' has also been created in the current directory ($(pwd))."
echo "Use './apply_update.sh' when new code for a specific file is provided."
echo "It will prompt for the file path and then let you paste the new content."
echo "---------------------------------------------------------------------"


# --- Final Instructions for the Initial Setup ---
echo ""
echo "---------------------------------------------------------------------"
echo "Threads Clone project successfully created in '$BASE_DIR' directory!"
echo "---------------------------------------------------------------------"
echo ""
echo "Initial Setup Next Steps:"
echo "1. VERY IMPORTANT: Review '$BASE_DIR/backend/.env_INSTRUCTIONS.txt' and create/populate '$BASE_DIR/backend/.env' with your actual secret keys."
echo ""
echo "2. Navigate to the backend: cd $BASE_DIR/backend"
echo "3. Create a Python virtual environment: python3 -m venv venv  (or python -m venv venv)"
echo "4. Activate the virtual environment:"
echo "   - macOS/Linux: source venv/bin/activate"
echo "   - Windows:     venv\\Scripts\\activate"
echo "5. Install backend dependencies: pip install -r requirements.txt"
echo "6. (Optional for schema changes) Initialize Flask-Migrate (ensure FLASK_APP is set):"
echo "   export FLASK_APP=run.py  (macOS/Linux) or set FLASK_APP=run.py (Windows)"
echo "   flask db init       (only once per project if 'migrations' folder is missing)"
echo "   flask db migrate -m \"Initial migration\""
echo "   flask db upgrade"
echo "   (Note: db.create_all() in app/__init__.py will create tables on first run if migrations are not used)"
echo ""
echo "7. Run the backend server: python run.py"
echo "   (The backend should be running on http://localhost:5001 or http://0.0.0.0:5001)"
echo ""
echo "8. Open the frontend: Navigate to the '$BASE_DIR/frontend/' directory in your file explorer"
echo "   and open 'index.html' in your web browser."
echo ""
echo "---------------------------------------------------------------------"
echo "For Future Updates to specific files:"
echo "1. The AI will provide the new code for a specific file."
echo "2. Run the './apply_update.sh' script (located in the same directory as '$BASE_DIR')."
echo "3. When prompted, enter the relative path of the file to update (e.g., backend/app/models.py)."
echo "4. Paste the new code provided by the AI."
echo "5. Type '__EOF__' on a new, empty line and press Enter to save the changes."
echo "---------------------------------------------------------------------"
echo "Happy Testing!"
